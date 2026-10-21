// Finding the Aerox 9 and talking to its configuration interface through hidapi.
//
// USB cable: vendor 0x1038, product 0x185A (0x1876 for the WOW edition).
// 2.4 GHz dongle: 0x1858 / 0x1874; commands get 0x40 OR'd into their first byte.
// Either way the commands go to the vendor interface on usage page 0xFFC0, report 0.
// Bluetooth: vendor 0x0111, product 0x185A; commands go out as report 4 with the
// same codes as the cable.

use crate::protocol::{write_commands, Settings};
use hidapi::{HidApi, HidDevice};
use serde::Serialize;
use std::ffi::CString;
use std::sync::Mutex;
use std::thread::sleep;
use std::time::Duration;

const VENDOR: u16 = 0x1038;
const WIRED: [u16; 2] = [0x185A, 0x1876];
const WIRELESS: [u16; 2] = [0x1858, 0x1874];
const BT_VENDOR: u16 = 0x0111;
const BT_PRODUCT: u16 = 0x185A;
const CONFIG_PAGE: u16 = 0xFFC0;
/// Every report on the configuration channel carries 64 bytes after its report ID.
const REPORT_LEN: usize = 64;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Connection {
    None,
    Usb,
    Dongle,
    Bluetooth,
    /// The mouse is there but the system won't let us open it (Linux without the udev rule).
    NoAccess,
}

struct Channel {
    path: CString,
    report_id: u8,
    flag: u8,
    connection: Connection,
}

#[derive(Serialize)]
pub struct Battery {
    pub percent: u8,
    pub charging: bool,
}

pub struct Hid {
    api: Mutex<Option<HidApi>>,
}

impl Hid {
    pub fn new() -> Self {
        Self { api: Mutex::new(HidApi::new().ok()) }
    }

    /// Where commands go right now, preferring the cable, then the dongle, then Bluetooth.
    fn channel(&self) -> Option<Channel> {
        let mut guard = self.api.lock().ok()?;
        let api = guard.as_mut()?;
        api.refresh_devices().ok()?;
        let mut best: Option<Channel> = None;
        for d in api.device_list() {
            let (vid, pid, page) = (d.vendor_id(), d.product_id(), d.usage_page());
            let found = if vid == VENDOR && page == CONFIG_PAGE && WIRED.contains(&pid) {
                Some((0, 0x00, Connection::Usb))
            } else if vid == VENDOR && page == CONFIG_PAGE && WIRELESS.contains(&pid) {
                Some((0, 0x40, Connection::Dongle))
            } else if vid == BT_VENDOR && pid == BT_PRODUCT && (page == CONFIG_PAGE || page < 0xFF00) {
                // Linux lists the Bluetooth mouse as one node (its first collection is the
                // pointer); Windows splits it per collection, so take the vendor one there.
                Some((4, 0x00, Connection::Bluetooth))
            } else {
                None
            };
            let Some((report_id, flag, connection)) = found else { continue };
            let rank = |c: Connection| match c {
                Connection::Usb => 3,
                Connection::Dongle => 2,
                Connection::Bluetooth => 1,
                Connection::None | Connection::NoAccess => 0,
            };
            let better = match &best {
                None => true,
                Some(b) => rank(connection) > rank(b.connection)
                    || (connection == Connection::Bluetooth && b.connection == Connection::Bluetooth && page == CONFIG_PAGE),
            };
            if better {
                best = Some(Channel { path: d.path().to_owned(), report_id, flag, connection });
            }
        }
        drop(guard);
        if let Some(ch) = &mut best {
            if self.open(&ch.path).is_err() {
                ch.connection = Connection::NoAccess;
                return best;
            }
        }
        // A dongle is there whether or not the mouse is linked to it; only a mouse that
        // answers counts. (An unlinked dongle replies 40 ff instead of the battery.)
        if let Some(ch) = &best {
            if ch.connection == Connection::Dongle && self.query_battery(ch).is_none() {
                return None;
            }
        }
        best
    }

    pub fn connection(&self) -> Connection {
        self.channel().map_or(Connection::None, |c| c.connection)
    }

    fn open(&self, path: &CString) -> Result<HidDevice, String> {
        let guard = self.api.lock().map_err(|_| "HID unavailable".to_string())?;
        let api = guard.as_ref().ok_or("HID unavailable")?;
        api.open_path(path).map_err(|e| format!("Couldn't open the mouse: {e}"))
    }

    fn send(dev: &HidDevice, ch: &Channel, payload: &[u8]) -> Result<(), String> {
        let mut buf = vec![0u8; REPORT_LEN + 1];
        buf[0] = ch.report_id;
        buf[1] = payload[0] | ch.flag;
        buf[2..1 + payload.len()].copy_from_slice(&payload[1..]);
        dev.write(&buf).map_err(|e| format!("Write failed: {e}"))?;
        Ok(())
    }

    /// Battery query 0x92: the reply's next byte is (level/5 + 1), top bit set while charging.
    pub fn battery(&self) -> Option<Battery> {
        self.query_battery(&self.channel()?)
    }

    fn query_battery(&self, ch: &Channel) -> Option<Battery> {
        let dev = self.open(&ch.path).ok()?;
        Self::send(&dev, ch, &[0x92]).ok()?;
        let mut buf = [0u8; 128];
        for _ in 0..5 {
            let n = dev.read_timeout(&mut buf, 200).ok()?;
            if n == 0 {
                continue;
            }
            // A dongle with no mouse linked answers 40 ff straight away.
            if buf[0] == 0x40 && n > 1 && buf[1] == 0xFF {
                return None;
            }
            // The reply may or may not lead with its report ID, depending on the platform.
            let head = &buf[..n.min(2)];
            if let Some(i) = head.iter().position(|b| b & 0xBF == 0x92) {
                let raw = *buf.get(i + 1)?;
                let level = ((raw & 0x7F) as i32 - 1) * 5;
                return Some(Battery { percent: level.clamp(0, 100) as u8, charging: raw & 0x80 != 0 });
            }
        }
        None
    }

    /// Writes buttons, CPI and polling rate, plus lighting when `lighting` is true, then saves.
    pub fn write(&self, settings: &Settings, lighting: bool) -> Result<(), String> {
        let ch = self.channel().ok_or("Mouse not found.")?;
        if ch.connection == Connection::NoAccess {
            return Err("No permission to reach the mouse.".into());
        }
        let dev = self.open(&ch.path)?;
        let pause = Duration::from_millis(if ch.report_id == 0 { 30 } else { 50 });
        for command in write_commands(settings, lighting) {
            Self::send(&dev, &ch, &command)?;
            sleep(pause);
        }
        Ok(())
    }
}
