// Opensteel — a tiny button remapper for the SteelSeries Aerox 9 Wireless.
//
// Writes bindings straight into the mouse's onboard memory, so they keep
// working with this app (and SteelSeries GG) closed.
//
// Protocol (reverse engineered by the rivalcfg project, flozz/rivalcfg#188):
//   Command 0x2A (wired) / 0x6A (2.4 GHz dongle), sent as 3 packets:
//     [cmd, 0x00, B1, B2, B3, TiltL, TiltR, CPI]
//     [cmd, 0x01, S3, S6, S9, S12, S2, S5]
//     [cmd, 0x02, S8, S11, S1, S4, S7, S10, ScrollUp, ScrollDown]
//   Each slot is 5 bytes: [action, code, 0, 0, 0].
//   CPI: [0x2D, count, active, codes…] (always sent as a single preset); polling rate: [0x2B, code].
//   Save to onboard memory: [0x11, 0x00]. Over 2.4 GHz every command has 0x40 set.

import SwiftUI
import SceneKit
import IOKit.hid

// MARK: - Actions

struct ActionCode: Codable, Hashable {
    var type: UInt8
    var code: UInt8 = 0

    var bytes: [UInt8] { [type, code, 0, 0, 0] }

    static let disabled = ActionCode(type: 0x00)
    static func mouse(_ n: UInt8) -> ActionCode { ActionCode(type: n) }
    static let scrollUp = ActionCode(type: 0x31)
    static let scrollDown = ActionCode(type: 0x32)
    static let panLeft = ActionCode(type: 0x33)
    static let panRight = ActionCode(type: 0x34)
    static func key(_ usage: UInt8) -> ActionCode { ActionCode(type: 0x51, code: usage) }
    static func media(_ usage: UInt8) -> ActionCode { ActionCode(type: 0x61, code: usage) }
}

struct ActionOption: Identifiable {
    let name: String
    let action: ActionCode
    var id: ActionCode { action }
}

struct ActionGroup: Identifiable {
    let name: String
    let options: [ActionOption]
    var id: String { name }
}

let actionCatalog: [ActionGroup] = {
    func keys(_ list: [(String, UInt8)]) -> [ActionOption] {
        list.map { ActionOption(name: $0.0, action: .key($0.1)) }
    }
    let letters = (0..<26).map { i -> (String, UInt8) in
        (String(UnicodeScalar(UInt8(65 + i))), UInt8(0x04 + i))
    }
    let digits: [(String, UInt8)] = (1...9).map { (n: Int) -> (String, UInt8) in ("\(n)", UInt8(0x1D + n)) }
        + [("0", 0x27)]
    let f1to12: [(String, UInt8)] = (1...12).map { (n: Int) -> (String, UInt8) in ("F\(n)", UInt8(0x39 + n)) }
    let f13to24: [(String, UInt8)] = (13...24).map { (n: Int) -> (String, UInt8) in ("F\(n)", UInt8(0x5B + n)) }
    let fkeys = f1to12 + f13to24
    let keypadDigits: [(String, UInt8)] = (1...9).map { (n: Int) -> (String, UInt8) in ("Keypad \(n)", UInt8(0x58 + n)) }
    let keypad: [(String, UInt8)] = keypadDigits + [
        ("Keypad 0", 0x62), ("Keypad .", 0x63), ("Keypad /", 0x54), ("Keypad *", 0x55),
        ("Keypad -", 0x56), ("Keypad +", 0x57), ("Keypad Enter", 0x58),
    ]
    return [
        ActionGroup(name: "Special", options: [
            ActionOption(name: "Disabled", action: .disabled),
            ActionOption(name: "Scroll up", action: .scrollUp),
            ActionOption(name: "Scroll down", action: .scrollDown),
            ActionOption(name: "Scroll left", action: .panLeft),
            ActionOption(name: "Scroll right", action: .panRight),
        ]),
        ActionGroup(name: "Mouse", options: [
            ActionOption(name: "Left click", action: .mouse(1)),
            ActionOption(name: "Right click", action: .mouse(2)),
            ActionOption(name: "Middle click", action: .mouse(3)),
            ActionOption(name: "Back (button 4)", action: .mouse(4)),
            ActionOption(name: "Forward (button 5)", action: .mouse(5)),
            ActionOption(name: "Button 6", action: .mouse(6)),
            ActionOption(name: "Button 7", action: .mouse(7)),
            ActionOption(name: "Button 8", action: .mouse(8)),
        ]),
        ActionGroup(name: "Media", options: [
            ActionOption(name: "Play / Pause", action: .media(0xCD)),
            ActionOption(name: "Next track", action: .media(0xB5)),
            ActionOption(name: "Previous track", action: .media(0xB6)),
            ActionOption(name: "Volume up", action: .media(0xE9)),
            ActionOption(name: "Volume down", action: .media(0xEA)),
            ActionOption(name: "Mute", action: .media(0xE2)),
        ]),
        ActionGroup(name: "Letters", options: keys(letters)),
        ActionGroup(name: "Numbers", options: keys(digits)),
        ActionGroup(name: "Symbols", options: keys([
            ("-", 0x2D), ("=", 0x2E), ("[", 0x2F), ("]", 0x30), ("\\", 0x31),
            (";", 0x33), ("'", 0x34), ("`", 0x35), (",", 0x36), (".", 0x37), ("/", 0x38),
        ])),
        ActionGroup(name: "Editing & navigation", options: keys([
            ("Return", 0x28), ("Escape", 0x29), ("Delete (backspace)", 0x2A),
            ("Forward delete", 0x4C), ("Tab", 0x2B), ("Space", 0x2C),
            ("Up arrow", 0x52), ("Down arrow", 0x51), ("Left arrow", 0x50), ("Right arrow", 0x4F),
            ("Home", 0x4A), ("End", 0x4D), ("Page up", 0x4B), ("Page down", 0x4E),
            ("Caps lock", 0x39),
        ])),
        ActionGroup(name: "Modifiers", options: keys([
            ("⌘ Command (left)", 0xE3), ("⌘ Command (right)", 0xE7),
            ("⌥ Option (left)", 0xE2), ("⌥ Option (right)", 0xE6),
            ("⌃ Control (left)", 0xE0), ("⌃ Control (right)", 0xE4),
            ("⇧ Shift (left)", 0xE1), ("⇧ Shift (right)", 0xE5),
        ])),
        ActionGroup(name: "Function keys", options: keys(fkeys)),
        ActionGroup(name: "Keypad", options: keys(keypad)),
    ]
}()

func actionName(_ a: ActionCode) -> String {
    for g in actionCatalog {
        if let o = g.options.first(where: { $0.action == a }) { return o.name }
    }
    return String(format: "Custom (0x%02X 0x%02X)", a.type, a.code)
}

// MARK: - Button slots

struct Slot: Identifiable {
    let id: String
    let label: String
    let defaultAction: ActionCode
}

// Left and right click are never remapped; see `fixedActions`.
let mainSlots: [Slot] = [
    Slot(id: "B3", label: "Wheel click", defaultAction: .mouse(3)),
    Slot(id: "CPI", label: "Top button", defaultAction: .disabled),
    Slot(id: "SU", label: "Scroll up", defaultAction: .scrollUp),
    Slot(id: "SD", label: "Scroll down", defaultAction: .scrollDown),
]

// Factory default for the side grid is keys 1…9, 0, -, =.
let sideDefaultKeys: [UInt8] = [0x1E, 0x1F, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x2D, 0x2E]
let sideSlots: [Slot] = (1...12).map {
    Slot(id: "S\($0)", label: "Side \($0)", defaultAction: .key(sideDefaultKeys[$0 - 1]))
}

// The side grid is 4 buttons long and 3 tall, numbered up each column from the
// front-bottom (1-2-3, 4-5-6, …) to 12 at the back-top. The firmware scans it
// row by row, which is why the packets group 1-4-7-10, 2-5-8-11 and 3-6-9-12.
let sideGridColumns = 4
let sideGridRows = 3
/// `row` 0 is the top row.
func sideNumber(column: Int, row: Int) -> Int { column * sideGridRows + (sideGridRows - 1 - row) + 1 }
let sideSlotsInGridOrder: [Slot] = (0..<sideGridRows).flatMap { row in
    (0..<sideGridColumns).map { column in sideSlots[sideNumber(column: column, row: row) - 1] }
}

// Slots that are always written with the same action: left/right click, and the
// tilt slots in the protocol that the Aerox 9 has no hardware for.
let fixedActions: [String: ActionCode] = ["B1": .mouse(1), "B2": .mouse(2), "TL": .panLeft, "TR": .panRight]

let packetLayout: [[String]] = [
    ["B1", "B2", "B3", "TL", "TR", "CPI"],
    ["S3", "S6", "S9", "S12", "S2", "S5"],
    ["S8", "S11", "S1", "S4", "S7", "S10", "SU", "SD"],
]

let allSlots = mainSlots + sideSlots
let buttonSlotOrder: [String] = packetLayout.flatMap { $0 }
let defaultMapping: [String: ActionCode] = Dictionary(
    uniqueKeysWithValues: allSlots.map { ($0.id, $0.defaultAction) }
)


// MARK: - Sensitivity & polling

// TrueMove Air sensor codes for 100…18000 CPI in steps of 100 (from rivalcfg).
let cpiCodes: [UInt8] = [
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
]

let cpiRange: ClosedRange<Int> = 100...18000
let defaultCPI = 800

// Command 0x2B: 0x00 = 1000 Hz … 0x03 = 125 Hz.
let pollingRates = [125, 250, 500, 1000]
func pollingCode(_ hz: Int) -> UInt8 {
    switch hz { case 125: return 0x03; case 250: return 0x02; case 500: return 0x01; default: return 0x00 }
}

func cpiCode(_ cpi: Int) -> UInt8 {
    let clamped = min(max(cpi, cpiRange.lowerBound), cpiRange.upperBound)
    return cpiCodes[(clamped + 50) / 100 - 1]
}

struct MouseSettings: Codable {
    var mapping: [String: ActionCode] = defaultMapping
    var cpi = defaultCPI
    var pollingRate = 1000
    var colourCycle = false      // lighting at startup: off, or the mouse's built-in colour cycle
    var clickFlash = false       // light up on click, independent of the above
    var clickFlashHex = "FFFFFF"

    init() {}

    // Settings saved before a field existed still load; missing fields keep their defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MouseSettings()
        mapping = try c.decodeIfPresent([String: ActionCode].self, forKey: .mapping) ?? d.mapping
        cpi = try c.decodeIfPresent(Int.self, forKey: .cpi) ?? d.cpi
        pollingRate = try c.decodeIfPresent(Int.self, forKey: .pollingRate) ?? d.pollingRate
        colourCycle = try c.decodeIfPresent(Bool.self, forKey: .colourCycle) ?? d.colourCycle
        clickFlash = try c.decodeIfPresent(Bool.self, forKey: .clickFlash) ?? d.clickFlash
        clickFlashHex = try c.decodeIfPresent(String.self, forKey: .clickFlashHex) ?? d.clickFlashHex
    }
}

/// "FF8800" or "#ff8800" → (255, 136, 0); nil unless exactly six hex digits.
func rgb(fromHex hex: String) -> (UInt8, UInt8, UInt8)? {
    let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
    return (UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF))
}

// Bluetooth LE reports at most every 7.5 ms, so the mouse runs at 133 Hz there
// whatever polling rate is stored (measured on the user's mouse).
let bluetoothPollingRate = 133

// MARK: - HID

enum Connection: Equatable {
    case none, usb, dongle, bluetooth

    /// Settings can be written over every connection: the 0xFFC0 interface on USB and the
    /// dongle, and report 4 over Bluetooth (the firmware accepts it; only GG stopped using it).
    var canEdit: Bool { self != .none }

    var label: String {
        switch self {
        case .none: return "Not connected"
        case .usb: return "USB cable"
        case .dongle: return "2.4 GHz dongle"
        case .bluetooth: return "Bluetooth"
        }
    }
}

enum MouseError: LocalizedError {
    case notFound, openFailed(IOReturn), writeFailed(IOReturn)
    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Mouse not found."
        case .openFailed(let r): return String(format: "Couldn't open the mouse (IOReturn 0x%08X).", r)
        case .writeFailed(let r): return String(format: "Write failed (IOReturn 0x%08X).", r)
        }
    }
}

final class AeroxHID {
    static let vendorID = 0x1038
    static let bluetoothVendorID = 0x0111
    static let bluetoothProductID = 0x185A
    static let wiredIDs: Set<Int> = [0x185A, 0x1876]
    static let wirelessIDs: Set<Int> = [0x1858, 0x1874]

    /// Called on the main thread for every button/key the mouse reports: (usage page, usage, pressed).
    var onInput: ((Int, Int, Bool) -> Void)?
    /// Called on the main thread with the mouse's physical-button bitmask (vendor report 0xFFC1/0xF0).
    /// Bit n is the n-th slot of `packetLayout`, flattened: bit 0 = left click, bit 14 = side 1…
    var onButtons: ((UInt64) -> Void)?
    private(set) var keysSeized = false

    // Config interface, pointer interface and the Bluetooth device. Never seized.
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOHIDOptionsType(kIOHIDOptionsTypeNone))
    // The keyboard and consumer interfaces the side buttons type through (USB/dongle only).
    // Seized while Opensteel is the active app so presses only highlight.
    private let keyManager = IOHIDManagerCreate(kCFAllocatorDefault, IOHIDOptionsType(kIOHIDOptionsTypeNone))
    private var keyManagerOpen = false

    init() {
        let ids = Self.wiredIDs.union(Self.wirelessIDs)
        func match(_ page: Int, _ usage: Int) -> [[String: Int]] {
            ids.map { [kIOHIDVendorIDKey: Self.vendorID, kIOHIDProductIDKey: $0,
                       kIOHIDPrimaryUsagePageKey: page, kIOHIDPrimaryUsageKey: usage] }
        }
        let main = match(0xFFC0, 1) + match(0xFFC1, 1) + match(0x01, 0x02)
            + [[kIOHIDVendorIDKey: Self.bluetoothVendorID, kIOHIDProductIDKey: Self.bluetoothProductID]]
        IOHIDManagerSetDeviceMatchingMultiple(manager, main as CFArray)
        IOHIDManagerSetDeviceMatchingMultiple(keyManager, (match(0x01, 0x06) + match(0x0C, 0x01)) as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOHIDValueCallback = { context, _, _, value in
            guard let context else { return }
            let me = Unmanaged<AeroxHID>.fromOpaque(context).takeUnretainedValue()
            let element = IOHIDValueGetElement(value)
            let page = Int(IOHIDElementGetUsagePage(element))
            let usage = Int(IOHIDElementGetUsage(element))
            if page == 0xFFC1 && usage == 0xF0 {
                let length = IOHIDValueGetLength(value)
                // The mouse also answers every command with a 64-byte reply on this usage;
                // only the 5-byte report is the button bitmask.
                guard length == 5 else { return }
                let bytes = IOHIDValueGetBytePtr(value)
                var mask: UInt64 = 0
                // Bytes 0-3 are the buttons; byte 4 is the scroll wheel.
                for i in 0..<min(length, 4) { mask |= UInt64(bytes[i]) << (8 * UInt64(i)) }
                me.onButtons?(mask)
                return
            }
            guard page == 0x07 || page == 0x09 || page == 0x0C else { return }
            me.onInput?(page, usage, IOHIDValueGetIntegerValue(value) != 0)
        }
        for m in [manager, keyManager] {
            IOHIDManagerRegisterInputValueCallback(m, callback, context)
            // Without a run loop the managers never hear about devices plugged in after launch.
            IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        }
        IOHIDManagerOpen(manager, IOHIDOptionsType(kIOHIDOptionsTypeNone))
    }

    /// Re-open after Input Monitoring is granted, so keyboard-capable devices deliver input.
    func reopen() {
        IOHIDManagerClose(manager, IOHIDOptionsType(kIOHIDOptionsTypeNone))
        IOHIDManagerOpen(manager, IOHIDOptionsType(kIOHIDOptionsTypeNone))
        if keyManagerOpen { setCapture(false); setCapture(true) }
    }

    /// Take the side buttons' key interfaces away from macOS (true) or give them back (false).
    func setCapture(_ on: Bool) {
        if on, !keyManagerOpen {
            keysSeized = IOHIDManagerOpen(keyManager, IOHIDOptionsType(kIOHIDOptionsTypeSeizeDevice)) == kIOReturnSuccess
            if !keysSeized { IOHIDManagerOpen(keyManager, IOHIDOptionsType(kIOHIDOptionsTypeNone)) }
            keyManagerOpen = true
        } else if !on, keyManagerOpen {
            IOHIDManagerClose(keyManager, IOHIDOptionsType(kIOHIDOptionsTypeNone))
            keyManagerOpen = false
            keysSeized = false
        }
    }

    private func intProp(_ dev: IOHIDDevice, _ key: String) -> Int {
        (IOHIDDeviceGetProperty(dev, key as CFString) as? NSNumber)?.intValue ?? 0
    }

    private var devices: [IOHIDDevice] {
        Array(IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? [])
    }

    /// The vendor-defined configuration interface of a connected Aerox 9.
    /// The mouse has two vendor interfaces (0xFFC0, 0xFFC1); only 0xFFC0 accepts output reports.
    private func configInterface() -> (device: IOHIDDevice, wireless: Bool)? {
        for dev in devices where intProp(dev, kIOHIDPrimaryUsagePageKey) == 0xFFC0
            && intProp(dev, kIOHIDMaxOutputReportSizeKey) > 0 {
            return (dev, Self.wirelessIDs.contains(intProp(dev, kIOHIDProductIDKey)))
        }
        return nil
    }

    func connection() -> Connection {
        if let (_, wireless) = configInterface() { return wireless ? .dongle : .usb }
        if devices.contains(where: { intProp($0, kIOHIDVendorIDKey) == Self.bluetoothVendorID }) { return .bluetooth }
        return .none
    }

    // MARK: Battery

    /// Called on the main thread with (percent, charging) when the mouse answers a battery query.
    var onBattery: ((Int, Bool) -> Void)?
    private var reportBuffers: [IOHIDDevice: UnsafeMutablePointer<UInt8>] = [:]

    /// Where vendor commands go: the 0xFFC0 interface over USB/dongle (report 0), or
    /// report 4 on the single Bluetooth device.
    private func commandChannel() -> (device: IOHIDDevice, reportID: Int, flag: UInt8)? {
        if let (dev, wireless) = configInterface() { return (dev, 0, wireless ? 0x40 : 0x00) }
        if let dev = devices.first(where: { intProp($0, kIOHIDVendorIDKey) == Self.bluetoothVendorID }) {
            return (dev, 4, 0x00)
        }
        return nil
    }

    /// Battery query 0x92: the reply's next byte is (level/5 + 1), top bit set while charging.
    func requestBattery() {
        guard let (dev, reportID, flag) = commandChannel() else { return }
        if reportBuffers[dev] == nil {
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
            reportBuffers[dev] = buffer
            let context = Unmanaged.passUnretained(self).toOpaque()
            IOHIDDeviceRegisterInputReportCallback(dev, buffer, 1024, { context, _, _, _, id, report, length in
                guard let context, id == 0 || id == 4 else { return }
                let me = Unmanaged<AeroxHID>.fromOpaque(context).takeUnretainedValue()
                let bytes = Array(UnsafeBufferPointer(start: report, count: length))
                guard let i = bytes.prefix(2).firstIndex(where: { $0 & 0xBF == 0x92 }), i + 1 < bytes.count else { return }
                let raw = bytes[i + 1]
                me.onBattery?(min(max((Int(raw & 0x7F) - 1) * 5, 0), 100), raw & 0x80 != 0)
            }, context)
        }
        let size = max(intProp(dev, kIOHIDMaxOutputReportSizeKey), 2)
        var out: [UInt8] = reportID == 0 ? [0x92 | flag] : [UInt8(reportID), 0x92 | flag]
        out += [UInt8](repeating: 0, count: max(0, size - out.count))
        IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, CFIndex(reportID), &out, out.count)
    }

    /// Writes buttons, CPI and polling rate, plus lighting when `lighting` is true, then saves.
    func write(_ settings: MouseSettings, lighting: Bool) throws {
        guard let (dev, reportID, flag) = commandChannel() else { throw MouseError.notFound }
        let r = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        guard r == kIOReturnSuccess else { throw MouseError.openFailed(r) }
        defer { IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone)) }

        let reportSize = max(intProp(dev, kIOHIDMaxOutputReportSizeKey), 1)
        func send(_ payload: [UInt8]) throws {
            // Over Bluetooth the report ID leads the data, as macOS expects for numbered reports.
            let body = (reportID == 0 ? [] : [UInt8(reportID)]) + payload
            var buf = body + [UInt8](repeating: 0, count: max(0, reportSize - body.count))
            let r = IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, CFIndex(reportID), &buf, buf.count)
            guard r == kIOReturnSuccess else { throw MouseError.writeFailed(r) }
            usleep(reportID == 0 ? 30_000 : 50_000)
        }

        for (index, ids) in packetLayout.enumerated() {
            var packet: [UInt8] = [0x2A | flag, UInt8(index)]
            for id in ids {
                packet += (fixedActions[id] ?? settings.mapping[id] ?? .disabled).bytes
            }
            try send(packet)
        }

        // CPI: [cmd, preset count, selected preset, code]
        // Exactly one preset, so there is nothing to cycle to.
        try send([0x2D | flag, 0x01, 0x00, cpiCode(settings.cpi)])

        try send([0x2B | flag, pollingCode(settings.pollingRate)])

        // Startup lighting: 00 = off, 02 = colour cycle (01 is a pulse). Zone colours are
        // deliberately not written: doing so overrides the effect until the mouse restarts.
        let startup: UInt8 = settings.colourCycle ? 0x02 : 0x00
        if lighting {
            try send([0x27 | flag, startup, 0x00])
            if settings.clickFlash, let (r, g, b) = rgb(fromHex: settings.clickFlashHex) {
                try send([0x26 | flag, 0x01, 0x00, r, g, b])
            } else {
                try send([0x26 | flag, 0x00, 0x00, 0x00, 0x00, 0x00])
            }
        }
        try send([0x11 | flag, 0x00])
        if lighting {
            // Repeated after the save so it shows now, not just at the next power-up. Over the
            // cable an effect also needs starting (22 ff); turning lights off applies by itself.
            try send([0x27 | flag, startup, 0x00])
            if settings.colourCycle { try send([0x22 | flag, 0xFF]) }
        }
    }
}

// MARK: - Model

@MainActor
final class Model: ObservableObject {
    @Published var settings = MouseSettings()
    @Published var connection: Connection = .none
    /// Whether the mouse was last seen over Bluetooth, kept across launches so a
    /// sleeping mouse still shows Bluetooth's fixed polling rate.
    @Published var lastOnBluetooth = UserDefaults.standard.bool(forKey: "lastOnBluetooth")
    @Published var message = ""
    @Published var isError = false
    @Published var writeState: WriteState = .idle
    enum WriteState { case idle, writing, saved }
    @Published var selected: String?
    @Published var hovered: String?
    @Published var flashing: Set<String> = []
    @Published var inputMonitoringGranted = true
    @Published var battery: (percent: Int, charging: Bool)?
    private var batteryTicks = 0

    let hid = AeroxHID()
    private var timer: Timer?
    private var flashToken = 0
    private var lastMouseKeyEvent = Date.distantPast
    private var lastButtonReport = Date.distantPast
    private var buttonMask: UInt64 = 0
    private var keyMonitor: Any?

    private static let storeURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Opensteel", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }()

    init() {
        if let data = try? Data(contentsOf: Self.storeURL),
           let saved = try? JSONDecoder().decode(MouseSettings.self, from: data) {
            settings = saved
            settings.mapping.merge(defaultMapping) { saved, _ in saved }
        }

        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeUnknown {
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
        hid.onBattery = { [weak self] percent, charging in
            MainActor.assumeIsolated { self?.battery = (percent, charging) }
        }
        hid.onButtons = { [weak self] mask in
            MainActor.assumeIsolated { self?.handleButtons(mask) }
        }
        hid.onInput = { [weak self] page, usage, down in
            MainActor.assumeIsolated { self?.handleInput(page: page, usage: usage, down: down) }
        }

        // Over Bluetooth the keys can't be seized, so swallow the ones that just
        // came from the mouse before they reach this window.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return event }
                let held = self.buttonMask & ~0b11 != 0
                guard held || Date().timeIntervalSince(self.lastMouseKeyEvent) < 0.3 else { return event }
                return nil
            }
        }

        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hid.setCapture(true) }
        }
        center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hid.setCapture(false) }
        }

        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        let now = hid.connection()
        if now != connection { batteryTicks = 0; if now == .none { battery = nil } }
        connection = now
        if now != .none, (now == .bluetooth) != lastOnBluetooth {
            lastOnBluetooth = now == .bluetooth
            UserDefaults.standard.set(lastOnBluetooth, forKey: "lastOnBluetooth")
        }
        // Ask right away on connect, then every ~30 s.
        if now != .none {
            if batteryTicks % 20 == 0 && writeState != .writing { hid.requestBattery() }
            batteryTicks += 1
        }
        let granted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        if granted && !inputMonitoringGranted { hid.reopen(); hid.requestBattery() }
        inputMonitoringGranted = granted
    }

    func action(for id: String) -> ActionCode {
        settings.mapping[id] ?? allSlots.first { $0.id == id }?.defaultAction ?? .disabled
    }

    /// The physical buttons currently held, straight from the mouse. Works for every
    /// button, including ones bound to Disabled.
    private func handleButtons(_ mask: UInt64) {
        let pressed = mask & ~buttonMask
        buttonMask = mask
        guard NSApp.isActive else { return }
        lastButtonReport = Date()
        // Left/right click are plain clicks; anything else is about to send a key we swallow.
        if mask & ~0b11 != 0 { lastMouseKeyEvent = Date() }
        let ids = buttonSlotOrder.enumerated()
            .filter { pressed & (1 << UInt64($0.offset)) != 0 && allSlots.map(\.id).contains($0.element) }
            .map(\.element)
        if !ids.isEmpty { flash(ids) }
    }

    /// Fallback when no button report arrived: work out the button from what it sent.
    private func handleInput(page: Int, usage: Int, down: Bool) {
        guard NSApp.isActive, down else { return }
        let sent: ActionCode
        switch page {
        case 0x07 where (0x04...0xE7).contains(usage): sent = .key(UInt8(usage))
        case 0x0C where (0x01...0xFF).contains(usage): sent = .media(UInt8(usage))
        case 0x09 where (3...8).contains(usage): sent = .mouse(UInt8(usage))  // left/right clicks are just clicks
        default: return
        }
        if page != 0x09 { lastMouseKeyEvent = Date() }
        guard Date().timeIntervalSince(lastButtonReport) > 0.3 else { return }
        let ids = allSlots.map(\.id).filter { action(for: $0) == sent }
        if !ids.isEmpty { flash(ids) }
    }

    private func flash(_ ids: [String]) {
        // A key bound to a mouse click is usually being used to click something in this
        // window, so it only flashes; taking the selection would fight with that click.
        if let first = ids.first(where: { !isMouseClick(action(for: $0)) }) { selected = first }
        flashing = Set(ids)
        flashToken += 1
        let token = flashToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            MainActor.assumeIsolated {
                if self?.flashToken == token { self?.flashing = [] }
            }
        }
    }

    private func isMouseClick(_ action: ActionCode) -> Bool {
        (1...8).contains(action.type) && action.code == 0
    }

    func markDirty() {
        message = "Unsaved changes. Click “Write to Mouse” to apply."
        isError = false
    }

    /// Lighting is only written once it has been changed here, so writing buttons never
    /// disturbs lighting someone set up elsewhere.
    private var lightingChanged = false
    func markLightingDirty() {
        lightingChanged = true
        markDirty()
    }

    func set(_ id: String, _ action: ActionCode) {
        settings.mapping[id] = action
        markDirty()
    }

    func resetDefaults() {
        settings = MouseSettings()
        lightingChanged = true
        message = "Defaults restored here. Click “Write to Mouse” to apply."
        isError = false
    }

    func writeToMouse() {
        if lightingChanged && settings.clickFlash && rgb(fromHex: settings.clickFlashHex) == nil {
            message = "The reactive colour needs six hex digits, like FF8800."
            isError = true
            return
        }
        guard writeState != .writing else { return }
        // A write takes about half a second; run it off the main thread so the window
        // stays responsive and the button can show progress.
        writeState = .writing
        message = ""
        isError = false
        let hid = self.hid, snapshot = settings, lighting = lightingChanged
        DispatchQueue.global(qos: .userInitiated).async {
            let failure: Error?
            do { try hid.write(snapshot, lighting: lighting); failure = nil } catch { failure = error }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.finishWrite(snapshot, lighting: lighting, failure: failure) }
            }
        }
    }

    private func finishWrite(_ written: MouseSettings, lighting: Bool, failure: Error?) {
        if let failure {
            writeState = .idle
            message = failure.localizedDescription
            isError = true
            return
        }
        if lighting { lightingChanged = false }
        if let data = try? JSONEncoder().encode(written) { try? data.write(to: Self.storeURL) }
        writeState = .saved
        message = "Saved to the mouse."
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            MainActor.assumeIsolated {
                if self?.writeState == .saved { self?.writeState = .idle }
            }
        }
    }
}

// MARK: - 3D mouse

// The system accent colour, the same one the sliders and buttons use.
let accentNS = NSColor.controlAccentColor
let accent = Color(nsColor: accentNS)

/// The Aerox 9 scan (model/Aerox9.mesh, made by tools/make_mesh.py) as a black
/// body, with the 12 side keys drawn as clean numbered caps where the scan measured
/// them. A highlighted key gets an orange ring around its cap.
final class MouseModel3D {
    let scene = SCNScene()
    let camera = SCNNode()
    private var keys: [String: SCNNode] = [:]      // "S1"…"S12"
    private var outlines: [String: SCNNode] = [:]

    init() {
        // Mesh space → scene space: mm → 1/100, z up → y up, front stays at -z, grid on -x.
        let mouse = SCNNode()
        mouse.simdTransform = simd_float4x4(columns: (
            SIMD4(-0.01, 0, 0, 0), SIMD4(0, 0, 0.01, 0), SIMD4(0, 0.01, 0, 0), SIMD4(0, 0, 0, 1)))
        scene.rootNode.addChildNode(mouse)

        if let url = Bundle.main.url(forResource: "Aerox9", withExtension: "mesh"),
           let data = try? Data(contentsOf: url) {
            build(from: data, into: mouse)
        }

        // Soft studio light: a bright-above, dark-below environment for reflections, a key
        // light from the camera side and a rim light behind to outline the shell.
        let sky = NSImage(size: NSSize(width: 64, height: 32), flipped: false) { rect in
            NSGradient(starting: NSColor(white: 0.04, alpha: 1), ending: NSColor(white: 0.95, alpha: 1))?
                .draw(in: rect, angle: 90)
            return true
        }
        scene.lightingEnvironment.contents = sky
        scene.lightingEnvironment.intensity = 0.9
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 120
        scene.rootNode.addChildNode(ambient)
        for (position, intensity) in [(SCNVector3(-1.6, 2, -1), 1500.0), (SCNVector3(1, 1.2, 1.6), 1300.0)] {
            let light = SCNNode()
            light.light = SCNLight()
            light.light?.type = .directional
            light.light?.intensity = CGFloat(intensity)
            light.position = position
            light.look(at: SCNVector3(0, 0, 0))
            scene.rootNode.addChildNode(light)
        }

        // Fixed view of the whole mouse from its button side, slightly from above.
        let lens = SCNCamera()
        lens.fieldOfView = 13
        lens.zNear = 0.01
        camera.camera = lens
        camera.position = SCNVector3(-2.75, 0.75, -0.25)
        camera.look(at: SCNVector3(0, 0.19, 0))
        scene.rootNode.addChildNode(camera)
    }

    private static func material(white: CGFloat, roughness: CGFloat, metalness: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor(white: white, alpha: 1)
        m.roughness.contents = roughness
        m.metalness.contents = metalness
        return m
    }

    /// Reads the format written by tools/make_mesh.py.
    private func build(from data: Data, into parent: SCNNode) {
        guard data.count > 12, data.prefix(4) == Data("OSM2".utf8) else { return }
        var offset = 4
        func read<T>(_ count: Int, as _: T.Type) -> [T] {
            let size = MemoryLayout<T>.stride * count
            defer { offset += size }
            return data.subdata(in: offset..<offset + size).withUnsafeBytes { Array($0.bindMemory(to: T.self)) }
        }
        let header: [UInt32] = read(2, as: UInt32.self)
        let vertexCount = Int(header[0]), triangleCount = Int(header[1])
        let positions: [Float] = read(vertexCount * 3, as: Float.self)
        let normals: [Float] = read(vertexCount * 3, as: Float.self)
        let indices: [UInt32] = read(triangleCount * 3, as: UInt32.self)

        func source(_ values: [Float], _ semantic: SCNGeometrySource.Semantic) -> SCNGeometrySource {
            SCNGeometrySource(data: Data(bytes: values, count: values.count * 4), semantic: semantic,
                              vectorCount: vertexCount, usesFloatComponents: true, componentsPerVector: 3,
                              bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
        }
        let body = SCNGeometry(sources: [source(positions, .vertex), source(normals, .normal)],
                               elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        // The body ignores the studio environment (which washed it out to charcoal) and
        // only takes the lights, with a faint sheen, so it reads as matte black.
        let shell = SCNMaterial()
        shell.lightingModel = .blinn
        shell.diffuse.contents = NSColor(white: 0.06, alpha: 1)
        shell.specular.contents = NSColor(white: 0.28, alpha: 1)
        shell.shininess = 0.25
        shell.isDoubleSided = true  // the scan has a few flipped faces
        body.materials = [shell]
        parent.addChildNode(SCNNode(geometry: body))

        for number in 1...12 {
            let f: [Float] = read(15, as: Float.self)
            let centre = SIMD3(f[0], f[1], f[2]), along = SIMD3(f[3], f[4], f[5])
            let up = SIMD3(f[6], f[7], f[8]), facing = SIMD3(f[9], f[10], f[11])
            let cap = KeyCap(number: number, width: CGFloat(f[12]), height: CGFloat(f[13]), lean: CGFloat(f[14]))
            let frame = SCNNode()
            frame.simdTransform = simd_float4x4(columns: (
                SIMD4(along, 0), SIMD4(up, 0), SIMD4(facing, 0), SIMD4(centre, 1)))
            parent.addChildNode(frame)
            let key = cap.capNode()
            let ring = cap.outlineNode()
            frame.addChildNode(key)
            frame.addChildNode(ring)
            keys["S\(number)"] = key
            outlines["S\(number)"] = ring
        }
    }

    func highlight(selected: String?, hovered: String? = nil, flashing: Set<String>, animated: Bool = true) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.12 : 0
        for (key, outline) in outlines {
            let pressed = flashing.contains(key) || selected == "ALL"
            // Pressed > selected > hovered, each clearly different: a press and a selection
            // both tint the key face (a press more strongly); hover is only a faint outline.
            if pressed || key == selected { outline.opacity = 1 }
            else if key == hovered { outline.opacity = 0.4 }
            else { outline.opacity = 0 }
            let tint: CGFloat = pressed ? 0.6 : key == selected ? 0.3 : 0
            keys[key]?.geometry?.firstMaterial?.emission.contents =
                accentNS.blended(withFraction: 1 - tint, of: .black) ?? NSColor.black
        }
        SCNTransaction.commit()
    }
}

/// One side key drawn as a clean cap: a slanted, rounded parallelogram with its number
/// printed on top, like the real keys. Its local frame is x along the key, y up it,
/// z out of the mouse, with the origin at the centre of the top face. Units are mm.
private struct KeyCap {
    let number: Int
    let width: CGFloat
    let height: CGFloat
    let lean: CGFloat  // how far the sides shift along per unit up

    static let depth: CGFloat = 1.6
    static let ink = NSColor(srgbRed: 0.8, green: 0.86, blue: 0.92, alpha: 1)

    /// The cap's corners grown by `margin`, going round from bottom-left.
    private func corners(margin: CGFloat) -> [CGPoint] {
        let w = width / 2 + margin, h = height / 2 + margin
        return [(-w, -h), (w, -h), (w, h), (-w, h)].map { CGPoint(x: $0.0 + lean * $0.1, y: $0.1) }
    }

    private func roundedPath(margin: CGFloat, radius: CGFloat) -> NSBezierPath {
        let c = corners(margin: margin)
        let path = NSBezierPath()
        path.move(to: CGPoint(x: (c[3].x + c[0].x) / 2, y: (c[3].y + c[0].y) / 2))
        for i in 0..<4 { path.appendArc(from: c[i], to: c[(i + 1) % 4], radius: radius) }
        path.close()
        path.flatness = 0.02
        return path
    }

    func capNode() -> SCNNode {
        let shape = SCNShape(path: roundedPath(margin: 0, radius: 0.9), extrusionDepth: Self.depth)
        shape.chamferRadius = 0.35
        let face = SCNMaterial()
        face.lightingModel = .physicallyBased
        face.diffuse.contents = labelImage()
        face.roughness.contents = 0.42
        face.metalness.contents = 0.35  // the real keys have a fine metallic sparkle
        let sides = SCNMaterial()
        sides.lightingModel = .physicallyBased
        sides.diffuse.contents = NSColor(white: 0.26, alpha: 1)
        sides.roughness.contents = 0.5
        sides.metalness.contents = 0.3
        let edge = face.copy() as! SCNMaterial
        edge.diffuse.contents = NSColor(white: 0.5, alpha: 1)
        shape.materials = [face, sides, sides, edge, sides]  // front, back, sides, front chamfer, back chamfer
        let node = SCNNode(geometry: shape)
        node.position = SCNVector3(0, 0, -Self.depth / 2 + 0.15)  // top face just proud of the scan
        return node
    }

    /// A thin orange ring just outside the cap, level with its top face.
    func outlineNode() -> SCNNode {
        let ring = roundedPath(margin: 0.75, radius: 1.4)
        ring.append(roundedPath(margin: 0.2, radius: 1.0).reversed)
        ring.windingRule = .evenOdd
        let shape = SCNShape(path: ring, extrusionDepth: 0.3)
        let glow = SCNMaterial()
        glow.lightingModel = .constant
        glow.diffuse.contents = accentNS
        glow.isDoubleSided = true
        shape.materials = [glow]
        let node = SCNNode(geometry: shape)
        node.position = SCNVector3(0, 0, 0.1)
        node.opacity = 0
        return node
    }

    /// The cap's top-face texture: grey with the key's number, mapped over its bounding box.
    private func labelImage() -> NSImage {
        let box = roundedPath(margin: 0, radius: 0.9).bounds
        let scale: CGFloat = 40  // pixels per mm
        let size = NSSize(width: box.width * scale, height: box.height * scale)
        return NSImage(size: size, flipped: false) { rect in
            NSColor(white: 0.56, alpha: 1).setFill()
            rect.fill()
            let text = "\(number)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: height * 0.48 * scale, weight: .medium),
                .foregroundColor: Self.ink,
            ]
            let textSize = text.size(withAttributes: attrs)
            text.draw(at: NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2), withAttributes: attrs)
            return true
        }
    }
}

struct MouseView3D: NSViewRepresentable {
    @ObservedObject var model: Model

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        let mouse = context.coordinator.mouse
        view.scene = mouse.scene
        view.pointOfView = mouse.camera
        view.allowsCameraControl = false  // a fixed picture, not something to drag around
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        context.coordinator.mouse.highlight(selected: model.selected, hovered: model.hovered, flashing: model.flashing)
    }

    final class Coordinator: NSObject {
        let mouse = MouseModel3D()
    }
}

/// `Opensteel --snapshot out.png [slotID|ALL] [close]` renders the 3D mouse to a PNG and exits.
func renderSnapshot(_ args: [String]) {
    guard let path = args.first else { return }
    let mouse = MouseModel3D()
    mouse.highlight(selected: args.dropFirst().first, flashing: [], animated: false)
    mouse.scene.background.contents = NSColor(white: 0.17, alpha: 1)  // the app's dark panel
    let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
    renderer.scene = mouse.scene
    renderer.pointOfView = mouse.camera
    if args.dropFirst(2).first == "close" {  // straight onto the key grid, for checking key shapes
        let lens = SCNCamera()
        lens.fieldOfView = 11
        let close = SCNNode()
        close.camera = lens
        close.position = SCNVector3(-1.7, 0.15, -0.06)
        close.look(at: SCNVector3(-0.315, 0.165, -0.06))
        mouse.scene.rootNode.addChildNode(close)
        renderer.pointOfView = close
    }
    let image = renderer.snapshot(atTime: 0, with: CGSize(width: 1240, height: 420), antialiasingMode: .multisampling4X)
    if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: path))
    }
}

// MARK: - UI

struct BatteryLabel: View {
    let percent: Int
    let charging: Bool

    var body: some View {
        let symbol = charging ? "battery.100.bolt"
            : percent > 87 ? "battery.100" : percent > 62 ? "battery.75"
            : percent > 37 ? "battery.50" : percent > 12 ? "battery.25" : "battery.0"
        HStack(spacing: 5) {
            Image(systemName: symbol).foregroundStyle(percent <= 15 && !charging ? Color.red : Color.secondary)
            Text("\(percent)%").monospacedDigit()
        }
        .font(.callout)
        .help(charging ? "Charging" : "Battery")
    }
}

struct ConnectionPill: View {
    let connection: Connection

    var body: some View {
        let color: Color = connection.canEdit ? .green : (connection == .bluetooth ? .blue : .gray)
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(connection.label)
            if !connection.canEdit {
                Text("·").foregroundStyle(.secondary)
                Image(systemName: "lock.fill").font(.caption2)
                Text("View only")
            }
        }
        .font(.callout)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Capsule().fill(Color.secondary.opacity(0.12)))
    }
}

struct SlotCard: View {
    let slot: Slot
    @ObservedObject var model: Model
    let editable: Bool

    var body: some View {
        let isSelected = model.selected == slot.id
        let isHovered = model.hovered == slot.id
        let isFlashing = model.flashing.contains(slot.id)
        Group {
            if editable {
                // The whole card is the menu button, not just the value text.
                Menu {
                    ForEach(actionCatalog) { group in
                        Menu(group.name) {
                            ForEach(group.options) { opt in
                                Button(opt.name) { model.set(slot.id, opt.action) }
                            }
                        }
                    }
                    Divider()
                    Button("Default (\(actionName(slot.defaultAction)))") { model.set(slot.id, slot.defaultAction) }
                } label: {
                    face
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .simultaneousGesture(TapGesture().onEnded { model.selected = slot.id })
            } else {
                face.onTapGesture { model.selected = slot.id }
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(
            isFlashing ? accent.opacity(0.4) : isSelected ? accent.opacity(0.18)
                : isHovered ? accent.opacity(0.06) : Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(
            isSelected ? accent : isHovered ? accent.opacity(0.4) : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1))
        .onHover { inside in
            if inside { model.hovered = slot.id } else if model.hovered == slot.id { model.hovered = nil }
        }
        .animation(.easeOut(duration: 0.1), value: isHovered)
        .animation(.easeOut(duration: 0.15), value: isFlashing)
    }

    /// Label and value, centred, filling the card so every part of it is clickable.
    private var face: some View {
        VStack(spacing: 3) {
            Text(slot.label).font(.caption).foregroundStyle(.secondary)
            Text(actionName(model.action(for: slot.id)))
                .font(.body.weight(.medium))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 46)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }
}

/// Read-only stand-in for a slider.
let cpiSliderMax = 5000

// One slider row shared by DPI and polling so the two sit evenly side by side:
// slider, number box, unit. A locked row ignores clicks rather than using
// .disabled, which greys the slider fill; an invisible overlay takes the hover
// so the lock's tooltip still shows.
struct SliderRow: View {
    @Binding var slider: Double
    let range: ClosedRange<Double>
    @Binding var number: Int
    let unit: String
    var lockedTip: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            Slider(value: $slider, in: range)
            HStack(spacing: 4) {
                TextField("", value: $number, format: .number.grouping(.never))
                    .multilineTextAlignment(.center)
                    .frame(width: 56)
                Text(unit).frame(width: 28, alignment: .leading)
            }
        }
        .allowsHitTesting(lockedTip == nil)
        .overlay {
            if let lockedTip { Color.clear.contentShape(Rectangle()).help(lockedTip) }
        }
    }
}

struct SensitivityView: View {
    @ObservedObject var model: Model
    let editable: Bool

    var body: some View {
        let cpi = model.settings.cpi
        Group {
            if editable {
                SliderRow(
                    slider: Binding(
                        get: { Double(min(cpi, cpiSliderMax)) },
                        set: { model.settings.cpi = Int(($0 / 100).rounded()) * 100; model.markDirty() }
                    ),
                    range: Double(cpiRange.lowerBound)...Double(cpiSliderMax),
                    number: Binding(
                        get: { model.settings.cpi },
                        set: {
                            let rounded = ($0 + 50) / 100 * 100
                            model.settings.cpi = min(max(rounded, cpiRange.lowerBound), cpiRange.upperBound)
                            model.markDirty()
                        }
                    ),
                    unit: "DPI"
                )
                .help("Type any value from 100 to 18000")
            } else {
                SliderRow(slider: .constant(Double(min(cpi, cpiSliderMax))),
                          range: Double(cpiRange.lowerBound)...Double(cpiSliderMax),
                          number: .constant(cpi), unit: "DPI", lockedTip: "Connect the mouse to edit.")
            }
        }.padding(.horizontal, 6).padding(.vertical, 2)
    }
}

struct LightingView: View {
    @ObservedObject var model: Model
    let editable: Bool

    var body: some View {
        let s = model.settings
        // The colour picker and the hex field edit the same stored hex.
        let colour = Binding<Color>(
            get: {
                rgb(fromHex: s.clickFlashHex).map {
                    Color(red: Double($0.0) / 255, green: Double($0.1) / 255, blue: Double($0.2) / 255)
                } ?? .white
            },
            set: { new in
                guard let c = NSColor(new).usingColorSpace(.sRGB) else { return }
                let byte = { (v: CGFloat) in Int((min(max(v, 0), 1) * 255).rounded()) }
                model.settings.clickFlashHex = String(format: "%02X%02X%02X",
                                                      byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
                model.markLightingDirty()
            }
        )
        HStack(spacing: 18) {
            Group {
                Picker("Lights", selection: Binding(
                    get: { s.colourCycle },
                    set: { model.settings.colourCycle = $0; model.markLightingDirty() }
                )) {
                    Text("Off").tag(false)
                    Text("Colour cycle").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
                // SteelSeries calls this "reactive": the lights flash this colour on each click.
                Toggle("Reactive", isOn: Binding(
                    get: { s.clickFlash },
                    set: { model.settings.clickFlash = $0; model.markLightingDirty() }
                ))
                if s.clickFlash {
                    HStack(spacing: 6) {
                        ColorPicker("Reactive colour", selection: colour, supportsOpacity: false)
                            .labelsHidden()
                        Text("#").foregroundStyle(.secondary)
                        TextField("FFFFFF", text: Binding(
                            get: { s.clickFlashHex },
                            set: {
                                let cleaned = String($0.uppercased().filter { "0123456789ABCDEF".contains($0) }.prefix(6))
                                model.settings.clickFlashHex = cleaned
                                model.markLightingDirty()
                            }
                        ))
                        .font(.body.monospaced())
                        .frame(width: 72)
                    }
                }
            }
            .allowsHitTesting(editable)
            Spacer(minLength: 0)
        }
        .overlay { if !editable { Color.clear.contentShape(Rectangle()).help("Connect the mouse to edit.") } }
        .padding(6)
    }
}

struct PollingView: View {
    @ObservedObject var model: Model

    var body: some View {
        let saved = model.settings.pollingRate
        let maxRate = Double(pollingRates.last!)
        let nearest = { (hz: Double) in pollingRates.min { abs(Double($0) - hz) < abs(Double($1) - hz) }! }
        Group {
            switch model.connection {
            case .bluetooth:
                SliderRow(slider: .constant(Double(bluetoothPollingRate)), range: 0...maxRate,
                          number: .constant(bluetoothPollingRate), unit: "Hz",
                          lockedTip: "Bluetooth is locked to \(bluetoothPollingRate) Hz. Set to \(saved) Hz for USB and 2.4 GHz.")
            case .usb, .dongle:
                SliderRow(
                    slider: Binding(
                        get: { Double(saved) },
                        set: { model.settings.pollingRate = nearest($0); model.markDirty() }
                    ),
                    range: 0...maxRate,
                    number: Binding(
                        get: { saved },
                        set: { model.settings.pollingRate = nearest(Double($0)); model.markDirty() }
                    ),
                    unit: "Hz"
                )
            case .none:
                let shown = model.lastOnBluetooth ? bluetoothPollingRate : saved
                SliderRow(slider: .constant(Double(shown)), range: 0...maxRate,
                          number: .constant(shown), unit: "Hz", lockedTip: "Connect the mouse to edit.")
            }
        }.padding(.horizontal, 6).padding(.vertical, 2)
    }
}

struct ContentView: View {
    @StateObject var model = Model()
    @State private var confirmingReset = false
    let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        let editable = model.connection.canEdit
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Opensteel").font(.title2.weight(.semibold))
                Text("Aerox 9 Wireless").foregroundStyle(.secondary)
                Spacer()
                if let battery = model.battery { BatteryLabel(percent: battery.percent, charging: battery.charging) }
                ConnectionPill(connection: model.connection)
            }

            VStack(alignment: .leading, spacing: 6) {
                MouseView3D(model: model)
                    .frame(height: 185)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.07)))
                if !model.inputMonitoringGranted { permissionHint }
            }

            GroupBox {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(sideSlotsInGridOrder) { SlotCard(slot: $0, model: model, editable: editable) }
                }.padding(4)
            }

            GroupBox("Top button & wheel") {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(mainSlots) { SlotCard(slot: $0, model: model, editable: editable) }
                }.padding(4)
            }

            HStack(alignment: .top, spacing: 12) {
                GroupBox("Sensitivity") {
                    SensitivityView(model: model, editable: editable)
                }
                GroupBox("Polling rate") { PollingView(model: model) }
            }

            GroupBox("Lighting") { LightingView(model: model, editable: editable) }

            // Always shown (greyed while the mouse is away) so the window keeps its size.
            HStack {
                Button("Reset to Defaults") { confirmingReset = true }
                    .disabled(!editable)
                    .confirmationDialog("Reset every button, DPI, polling rate and lighting to the defaults?",
                                        isPresented: $confirmingReset) {
                        Button("Reset", role: .destructive) { model.resetDefaults() }
                    } message: {
                        Text("Nothing changes on the mouse until you write.")
                    }
                Text(model.message)
                    .font(.callout)
                    .foregroundStyle(model.isError ? Color.red : Color.secondary)
                    .lineLimit(2)
                Spacer()
                Button { model.writeToMouse() } label: {
                    HStack(spacing: 6) {
                        switch model.writeState {
                        case .idle: Text("Write to Mouse")
                        case .writing: ProgressView().controlSize(.small); Text("Writing…")
                        case .saved: Image(systemName: "checkmark"); Text("Saved")
                        }
                    }
                    .frame(minWidth: 120)
                }
                .keyboardShortcut(.defaultAction)
                .tint(model.writeState == .saved ? .green : nil)
                .disabled(model.writeState == .writing || !editable)
                .animation(.easeOut(duration: 0.15), value: model.writeState)
            }
        }
        .padding(18)
        .frame(width: 660)
        .animation(.easeInOut(duration: 0.2), value: editable)
    }

    /// Only shown when Input Monitoring is missing; the 3D mouse shows presses itself.
    private var permissionHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "hand.raised")
            Text("Allow Input Monitoring for battery level and button highlights.")
            Button("Open Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
            }.buttonStyle(.link)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

@main
struct OpensteelApp: App {
    init() {
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot") {
            renderSnapshot(Array(CommandLine.arguments.dropFirst(i + 1)))
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup("Opensteel") { ContentView() }
            .windowResizability(.contentSize)
    }
}
