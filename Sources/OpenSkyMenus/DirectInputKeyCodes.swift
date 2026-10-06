// DirectInput scan codes (`DIK_*`, Microsoft dinput.h; the install's
// keyboard_english.txt lists the same codes) to macOS virtual key codes (`kVK_*`,
// Carbon HIToolbox Events.h), matched by physical key position on a US keyboard.

import Foundation

nonisolated public enum DirectInputKeyCodes {
    /// Scan code to macOS key code. Windows keys map to Command.
    public static let macKeyCodes: [UInt32: UInt16] = [
        0x01: 53, 0x02: 18, 0x03: 19, 0x04: 20, 0x05: 21, 0x06: 23, 0x07: 22, 0x08: 26,
        0x09: 28, 0x0A: 25, 0x0B: 29, 0x0C: 27, 0x0D: 24, 0x0E: 51, 0x0F: 48,
        0x10: 12, 0x11: 13, 0x12: 14, 0x13: 15, 0x14: 17, 0x15: 16, 0x16: 32, 0x17: 34,
        0x18: 31, 0x19: 35, 0x1A: 33, 0x1B: 30, 0x1C: 36, 0x1D: 59,
        0x1E: 0, 0x1F: 1, 0x20: 2, 0x21: 3, 0x22: 5, 0x23: 4, 0x24: 38, 0x25: 40,
        0x26: 37, 0x27: 41, 0x28: 39, 0x29: 50, 0x2A: 56, 0x2B: 42,
        0x2C: 6, 0x2D: 7, 0x2E: 8, 0x2F: 9, 0x30: 11, 0x31: 45, 0x32: 46, 0x33: 43,
        0x34: 47, 0x35: 44, 0x36: 60, 0x37: 67, 0x38: 58, 0x39: 49, 0x3A: 57,
        0x3B: 122, 0x3C: 120, 0x3D: 99, 0x3E: 118, 0x3F: 96, 0x40: 97, 0x41: 98, 0x42: 100,
        0x43: 101, 0x44: 109, 0x57: 103, 0x58: 111,
        0x47: 89, 0x48: 91, 0x49: 92, 0x4A: 78, 0x4B: 86, 0x4C: 87, 0x4D: 88, 0x4E: 69,
        0x4F: 83, 0x50: 84, 0x51: 85, 0x52: 82, 0x53: 65, 0x9C: 76, 0xB5: 75,
        0x9D: 62, 0xB8: 61,
        0xC7: 115, 0xC8: 126, 0xC9: 116, 0xCB: 123, 0xCD: 124, 0xCF: 119, 0xD0: 125,
        0xD1: 121, 0xD2: 114, 0xD3: 117, 0xDB: 55, 0xDC: 54
    ]

    public static let scanCodes: [UInt16: UInt32] = Dictionary(
        macKeyCodes.map { ($0.value, $0.key) }, uniquingKeysWith: min
    )

    public static func macKeyCode(_ scanCode: UInt32) -> UInt16? {
        macKeyCodes[scanCode]
    }

    public static func scanCode(_ macKeyCode: UInt16) -> UInt32? {
        scanCodes[macKeyCode]
    }

    /// Modifier keys arrive as a flag change, not a key down.
    public static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62]

    /// Short names for the keys a Mac keyboard prints differently, used when the
    /// install's key name table is missing.
    public static func fallbackName(_ scanCode: UInt32) -> String {
        switch scanCode {
        case 0x1D: "L-Ctrl"
        case 0x2A: "L-Shift"
        case 0x38: "L-Alt"
        case 0x39: "Space"
        case 0x0F: "Tab"
        case 0x01: "Esc"
        case 0x3A: "CapsLock"
        case 0x1C: "Enter"
        default: letterName(scanCode) ?? String(format: "0x%02X", scanCode)
        }
    }

    /// The US keyboard rows of the DirectInput scan code table.
    private static let letterRows: [(first: UInt32, keys: String)] = [
        (0x02, "1234567890"), (0x10, "QWERTYUIOP"), (0x1E, "ASDFGHJKL"), (0x2C, "ZXCVBNM")
    ]

    private static func letterName(_ scanCode: UInt32) -> String? {
        for row in letterRows where scanCode >= row.first {
            let offset = Int(scanCode - row.first)
            if offset < row.keys.count {
                return String(Array(row.keys)[offset])
            }
        }
        return nil
    }
}
