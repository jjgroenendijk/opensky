// Synthetic Havok binary tagfile writer. It emits the same item stream a real
// `.hkt` holds, built in code, so tests never read a game file.

import Foundation

/// Appends tagfile items. The caller writes the stream in order, as a real
/// writer would, and the helpers only encode numbers and strings.
public struct HKTagfileFixture: Sendable {
    public private(set) var data = Data()
    private var strings: [String] = ["", "\u{0}"]

    public init(magic0: UInt32 = 0xCAB0_0D1E, magic1: UInt32 = 0xD011_FACE) {
        for word in [magic0, magic1] {
            withUnsafeBytes(of: word.littleEndian) { data.append(contentsOf: $0) }
        }
    }

    /// A varint whose low bit is the sign.
    public mutating func int(_ value: Int) {
        var raw = UInt64(value.magnitude) << 1 | (value < 0 ? 1 : 0)
        repeat {
            var byte = UInt8(raw & 0x7F)
            raw >>= 7
            if raw != 0 {
                byte |= 0x80
            }
            data.append(byte)
        } while raw != 0
    }

    /// Writes a new string once and a back reference after that.
    public mutating func string(_ text: String) {
        if text.isEmpty {
            int(0)
            return
        }
        if let index = strings.firstIndex(of: text) {
            int(-index)
            return
        }
        strings.append(text)
        let bytes = Data(text.utf8)
        int(bytes.count)
        data.append(bytes)
    }

    public mutating func bytes(_ values: [UInt8]) {
        data.append(contentsOf: values)
    }

    public mutating func float(_ value: Float) {
        withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
    }

    public mutating func fileInfo(version: Int) {
        int(1)
        int(version)
    }

    /// One member of a class definition: its name, type word, and class name.
    public struct Member: Sendable {
        let name: String
        let type: Int
        let className: String?

        public init(_ name: String, _ type: Int, _ className: String? = nil) {
            self.name = name
            self.type = type
            self.className = className
        }
    }

    public mutating func classDefinition(
        _ name: String,
        version: Int = 0,
        parent: Int = 0,
        members: [Member]
    ) {
        int(2)
        string(name)
        int(version)
        int(parent)
        int(members.count)
        for member in members {
            string(member.name)
            int(member.type)
            if let className = member.className {
                string(className)
            }
        }
    }

    /// Starts a remembered object (tag 4) or a plain one (tag 3).
    public mutating func object(classIndex: Int, remembered: Bool = true) {
        int(remembered ? 4 : 3)
        int(classIndex)
    }

    public mutating func end() {
        int(7)
    }
}
