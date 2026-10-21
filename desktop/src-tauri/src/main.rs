// Opensteel — button, DPI and lighting settings for the SteelSeries Aerox 9 Wireless,
// written straight into the mouse's onboard memory so they keep working with this app
// (and SteelSeries GG) closed. The window is a web page in ui/; this side talks to the mouse.

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod hid;
mod protocol;

use hid::{Battery, Connection, Hid};
use protocol::Settings;
use std::path::PathBuf;
use tauri::{AppHandle, Manager, State};

fn settings_path(app: &AppHandle) -> Option<PathBuf> {
    let dir = app.path().app_data_dir().ok()?;
    std::fs::create_dir_all(&dir).ok()?;
    Some(dir.join("settings.json"))
}

#[tauri::command]
fn connection(hid: State<'_, Hid>) -> Connection {
    hid.connection()
}

#[tauri::command]
async fn battery(hid: State<'_, Hid>) -> Result<Option<Battery>, ()> {
    Ok(hid.battery())
}

/// The settings last written to the mouse, or the defaults.
#[tauri::command]
fn load_settings(app: AppHandle) -> Settings {
    let mut s = settings_path(&app)
        .and_then(|p| std::fs::read(p).ok())
        .and_then(|data| serde_json::from_slice::<Settings>(&data).ok())
        .unwrap_or_default();
    s.fill_defaults();
    s
}

#[tauri::command]
fn default_settings() -> Settings {
    Settings::default()
}

/// Writes to the mouse and, once that worked, remembers what was written.
#[tauri::command]
async fn write_settings(app: AppHandle, hid: State<'_, Hid>, settings: Settings, lighting: bool) -> Result<(), String> {
    hid.write(&settings, lighting)?;
    if let (Some(path), Ok(json)) = (settings_path(&app), serde_json::to_vec(&settings)) {
        let _ = std::fs::write(path, json);
    }
    Ok(())
}

/// The system accent colour as "#rrggbb", where the platform has one.
#[tauri::command]
fn accent_colour() -> Option<String> {
    #[cfg(windows)]
    {
        use winreg::{enums::HKEY_CURRENT_USER, RegKey};
        let dwm = RegKey::predef(HKEY_CURRENT_USER).open_subkey("Software\\Microsoft\\Windows\\DWM").ok()?;
        let abgr: u32 = dwm.get_value("AccentColor").ok()?;
        let (r, g, b) = (abgr & 0xFF, (abgr >> 8) & 0xFF, (abgr >> 16) & 0xFF);
        return Some(format!("#{r:02x}{g:02x}{b:02x}"));
    }
    #[allow(unreachable_code)]
    None
}

fn main() {
    tauri::Builder::default()
        .manage(Hid::new())
        .setup(|app| {
            // The page shows the window once it has sized it; this is only a fallback.
            let handle = app.handle().clone();
            std::thread::spawn(move || {
                std::thread::sleep(std::time::Duration::from_secs(3));
                if let Some(w) = handle.get_webview_window("main") {
                    let _ = w.show();
                }
            });
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            connection,
            battery,
            load_settings,
            default_settings,
            write_settings,
            accent_colour
        ])
        .run(tauri::generate_context!())
        .expect("error while running Opensteel");
}
