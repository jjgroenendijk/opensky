// Four-character type code ("TES4", "GRUP", "HEDR") as used across Bethesda
// formats (plugin records/fields, DDS). Kept as the raw little-endian UInt32
// so walking millions of records/fields allocates no strings.

import Foundation

nonisolated struct FourCC: Hashable {
    /// The four bytes as read little-endian (first character in the low byte).
    let rawValue: UInt32
}

extension FourCC: ExpressibleByStringLiteral {
    /// Programmer-supplied literals only (`"WRLD"`); traps on wrong length.
    init(stringLiteral value: StringLiteralType) {
        let bytes = Array(value.utf8)
        precondition(bytes.count == 4, "FourCC literal must be exactly 4 bytes")
        self.init(
            rawValue: UInt32(bytes[0])
                | UInt32(bytes[1]) << 8
                | UInt32(bytes[2]) << 16
                | UInt32(bytes[3]) << 24
        )
    }
}

nonisolated extension FourCC: CustomStringConvertible {
    var description: String {
        let bytes = withUnsafeBytes(of: rawValue.littleEndian) { Array($0) }
        guard
            bytes.allSatisfy({ (0x20 ... 0x7E).contains($0) }),
            let text = String(bytes: bytes, encoding: .ascii)
        else {
            return String(format: "0x%08X", rawValue)
        }
        return text
    }
}

extension BinaryReader {
    mutating func readFourCC() throws -> FourCC {
        try FourCC(rawValue: readUInt32())
    }
}
