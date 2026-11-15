// Four-character type code ("TES4", "GRUP", "HEDR") as used across Bethesda
// formats (plugin records/fields, DDS). Kept as the raw little-endian UInt32
// so walking millions of records/fields allocates no strings.

import Foundation

nonisolated public struct FourCC: Hashable, Sendable {
    /// The four bytes as read little-endian (first character in the low byte).
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

nonisolated extension FourCC: ExpressibleByStringLiteral {
    public typealias StringLiteralType = StaticString

    /// Programmer-supplied literals only (`"WRLD"`). A literal of the wrong length gives
    /// `invalidLiteral`, which no file holds. Inlined so each `case "WRLD":` of a field
    /// switch reads four constant bytes, which the optimiser folds into one integer.
    @inlinable @inline(__always)
    public init(stringLiteral value: StaticString) {
        guard value.hasPointerRepresentation, value.utf8CodeUnitCount == 4 else {
            self.init(rawValue: 0)
            return
        }
        let bytes = unsafe value.utf8Start
        self.init(
            rawValue: unsafe UInt32(bytes[0]) | UInt32(bytes[1]) << 8
                | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
        )
    }

    fileprivate static func packed(_ bytes: [UInt8]) -> UInt32 {
        UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
    }
}

nonisolated extension FourCC {
    /// Four zero bytes: a code literal of the wrong length. A record or field signature
    /// is printable ASCII, so this never matches one.
    static let invalidLiteral = FourCC(rawValue: 0)

    /// Code text known only at run time, such as a code a record or table holds. Text
    /// that is not four bytes gives `invalidLiteral`, as a wrong literal does.
    public init(code: String) {
        let bytes = Array(code.utf8)
        self.init(rawValue: bytes.count == 4 ? Self.packed(bytes) : Self.invalidLiteral.rawValue)
    }

    /// Text from a user, such as a command-line option: four ASCII characters, or nil.
    public init?(text: String) {
        let bytes = Array(text.utf8)
        guard bytes.count == 4, bytes.allSatisfy({ (0x20 ... 0x7E).contains($0) }) else {
            return nil
        }
        self.init(rawValue: Self.packed(bytes))
    }
}

nonisolated extension FourCC: CustomStringConvertible {
    public var description: String {
        let bytes = withUnsafeBytes(of: rawValue.littleEndian) { unsafe Array($0) }
        guard
            bytes.allSatisfy({ (0x20 ... 0x7E).contains($0) }),
            let text = String(bytes: bytes, encoding: .ascii)
        else {
            return unsafe String(format: "0x%08X", rawValue)
        }
        return text
    }
}

nonisolated extension BinaryReader {
    public mutating func readFourCC() throws -> FourCC {
        try FourCC(rawValue: readUInt32())
    }
}
