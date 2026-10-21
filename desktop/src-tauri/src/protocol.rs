// The Aerox 9 Wireless configuration protocol, shared by every connection.
//
// Button mapping (reverse engineered by the rivalcfg project, flozz/rivalcfg#188):
//   Command 0x2A, sent as 3 packets:
//     [0x2A, 0x00, B1, B2, B3, TiltL, TiltR, CPI]
//     [0x2A, 0x01, S3, S6, S9, S12, S2, S5]
//     [0x2A, 0x02, S8, S11, S1, S4, S7, S10, ScrollUp, ScrollDown]
//   Each slot is 5 bytes: [action, code, 0, 0, 0].
// CPI: [0x2D, count, active, codes…] (always a single preset). Polling: [0x2B, code].
// Lighting: [0x27, mode, 0] startup effect, [0x26, on, 0, R, G, B] click flash.
// Save to onboard memory: [0x11, 0x00]. Through the 2.4 GHz dongle every command has 0x40 set.

use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ActionCode {
    #[serde(rename = "type")]
    pub kind: u8,
    #[serde(default)]
    pub code: u8,
}

impl ActionCode {
    const fn new(kind: u8, code: u8) -> Self {
        Self { kind, code }
    }
    pub const DISABLED: Self = Self::new(0x00, 0);
    const fn mouse(n: u8) -> Self {
        Self::new(n, 0)
    }
    const SCROLL_UP: Self = Self::new(0x31, 0);
    const SCROLL_DOWN: Self = Self::new(0x32, 0);
    const PAN_LEFT: Self = Self::new(0x33, 0);
    const PAN_RIGHT: Self = Self::new(0x34, 0);
    const fn key(usage: u8) -> Self {
        Self::new(0x51, usage)
    }

    fn bytes(self) -> [u8; 5] {
        [self.kind, self.code, 0, 0, 0]
    }
}

// The side grid's factory default is keys 1…9, 0, -, =.
const SIDE_DEFAULT_KEYS: [u8; 12] = [0x1E, 0x1F, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x2D, 0x2E];

pub fn default_mapping() -> BTreeMap<String, ActionCode> {
    let mut m = BTreeMap::new();
    m.insert("B3".into(), ActionCode::mouse(3));
    m.insert("CPI".into(), ActionCode::DISABLED);
    m.insert("SU".into(), ActionCode::SCROLL_UP);
    m.insert("SD".into(), ActionCode::SCROLL_DOWN);
    for (i, key) in SIDE_DEFAULT_KEYS.iter().enumerate() {
        m.insert(format!("S{}", i + 1), ActionCode::key(*key));
    }
    m
}

/// Slots always written with the same action: left/right click (never remapped), and the
/// tilt slots the protocol has but the Aerox 9 has no hardware for.
fn fixed_action(id: &str) -> Option<ActionCode> {
    match id {
        "B1" => Some(ActionCode::mouse(1)),
        "B2" => Some(ActionCode::mouse(2)),
        "TL" => Some(ActionCode::PAN_LEFT),
        "TR" => Some(ActionCode::PAN_RIGHT),
        _ => None,
    }
}

pub const PACKET_LAYOUT: [&[&str]; 3] = [
    &["B1", "B2", "B3", "TL", "TR", "CPI"],
    &["S3", "S6", "S9", "S12", "S2", "S5"],
    &["S8", "S11", "S1", "S4", "S7", "S10", "SU", "SD"],
];

// TrueMove Air sensor codes for 100…18000 CPI in steps of 100 (from rivalcfg).
const CPI_CODES: [u8; 180] = [
    0x00, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x10, 0x11,
    0x12, 0x13, 0x14, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1D, 0x1E, 0x1F, 0x20, 0x21, 0x23,
    0x25, 0x26, 0x27, 0x28, 0x29, 0x2A, 0x2C, 0x2D, 0x2E, 0x2F, 0x30, 0x32, 0x33, 0x34, 0x35,
    0x36, 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3E, 0x3F, 0x40, 0x41, 0x42, 0x44, 0x45, 0x46, 0x47,
    0x48, 0x4A, 0x4B, 0x4C, 0x4D, 0x4E, 0x50, 0x51, 0x52, 0x53, 0x54, 0x56, 0x57, 0x58, 0x59,
    0x5A, 0x5C, 0x5D, 0x5E, 0x5F, 0x60, 0x62, 0x63, 0x64, 0x65, 0x66, 0x68, 0x69, 0x6A, 0x6B,
    0x6C, 0x6E, 0x6F, 0x70, 0x71, 0x72, 0x74, 0x75, 0x76, 0x77, 0x78, 0x7A, 0x7B, 0x7C, 0x7D,
    0x7E, 0x80, 0x81, 0x82, 0x83, 0x84, 0x86, 0x87, 0x88, 0x89, 0x8A, 0x8C, 0x8D, 0x8E, 0x8F,
    0x90, 0x92, 0x93, 0x94, 0x95, 0x96, 0x98, 0x99, 0x9A, 0x9B, 0x9C, 0x9E, 0x9F, 0xA0, 0xA1,
    0xA2, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xAA, 0xAB, 0xAC, 0xAD, 0xAE, 0xB0, 0xB1, 0xB2, 0xB3,
    0xB4, 0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xBB, 0xBC, 0xBD, 0xBF, 0xC0, 0xC2, 0xC3, 0xC4,
    0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCC, 0xCD, 0xCF, 0xD0, 0xD1, 0xD2, 0xD3, 0xD5, 0xD6,
];

fn cpi_code(cpi: u32) -> u8 {
    let clamped = cpi.clamp(100, 18000);
    CPI_CODES[((clamped + 50) / 100 - 1) as usize]
}

// Command 0x2B: 0x00 = 1000 Hz … 0x03 = 125 Hz.
fn polling_code(hz: u32) -> u8 {
    match hz {
        125 => 0x03,
        250 => 0x02,
        500 => 0x01,
        _ => 0x00,
    }
}

/// Same JSON as the Mac app's settings.json, so the two read each other's files.
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Settings {
    pub mapping: BTreeMap<String, ActionCode>,
    pub cpi: u32,
    pub polling_rate: u32,
    /// Lighting at startup: off, or the mouse's built-in colour cycle.
    pub colour_cycle: bool,
    /// Light up on click, independent of the above.
    pub click_flash: bool,
    pub click_flash_hex: String,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            mapping: default_mapping(),
            cpi: 800,
            polling_rate: 1000,
            colour_cycle: false,
            click_flash: false,
            click_flash_hex: "FFFFFF".into(),
        }
    }
}

impl Settings {
    /// Older or partial files keep the defaults for any slot they don't mention.
    pub fn fill_defaults(&mut self) {
        for (id, action) in default_mapping() {
            self.mapping.entry(id).or_insert(action);
        }
    }
}

/// "FF8800" or "#ff8800" → (255, 136, 0); None unless exactly six hex digits.
pub fn rgb_from_hex(hex: &str) -> Option<(u8, u8, u8)> {
    let digits = hex.strip_prefix('#').unwrap_or(hex);
    if digits.len() != 6 {
        return None;
    }
    let v = u32::from_str_radix(digits, 16).ok()?;
    Some(((v >> 16) as u8, (v >> 8) as u8, v as u8))
}

/// Every command a write sends, in order, without the dongle flag. Lighting is only
/// included when it was changed in the app, so writing buttons never disturbs lighting
/// set up elsewhere.
pub fn write_commands(s: &Settings, lighting: bool) -> Vec<Vec<u8>> {
    let mut out = Vec::new();
    for (index, ids) in PACKET_LAYOUT.iter().enumerate() {
        let mut packet = vec![0x2A, index as u8];
        for id in ids.iter() {
            let action = fixed_action(id)
                .or_else(|| s.mapping.get(*id).copied())
                .unwrap_or(ActionCode::DISABLED);
            packet.extend_from_slice(&action.bytes());
        }
        out.push(packet);
    }
    // Exactly one CPI preset, so there is nothing to cycle to.
    out.push(vec![0x2D, 0x01, 0x00, cpi_code(s.cpi)]);
    out.push(vec![0x2B, polling_code(s.polling_rate)]);

    // Startup lighting: 00 = off, 02 = colour cycle (01 is a pulse). Zone colours are
    // deliberately not written: doing so overrides the effect until the mouse restarts.
    let startup = if s.colour_cycle { 0x02 } else { 0x00 };
    if lighting {
        out.push(vec![0x27, startup, 0x00]);
        match (s.click_flash, rgb_from_hex(&s.click_flash_hex)) {
            (true, Some((r, g, b))) => out.push(vec![0x26, 0x01, 0x00, r, g, b]),
            _ => out.push(vec![0x26, 0x00, 0x00, 0x00, 0x00, 0x00]),
        }
    }
    out.push(vec![0x11, 0x00]);
    if lighting {
        // Repeated after the save so it shows now, not just at the next power-up. Over the
        // cable an effect also needs starting (22 ff); turning lights off applies by itself.
        out.push(vec![0x27, startup, 0x00]);
        if s.colour_cycle {
            out.push(vec![0x22, 0xFF]);
        }
    }
    out
}
