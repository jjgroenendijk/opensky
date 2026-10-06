// Failure modes of the Skyrim save (`.ess`) readers. No `BinaryReaderError` escapes:
// running out of bytes is `truncated(context:)`, naming the structure. See
// docs/formats/ess.md.

import Foundation

nonisolated public enum ESSError: Error, Equatable, Sendable {
    /// The first 13 bytes are not ASCII "TESV_SAVEGAME".
    case badMagic
    /// A header version this build does not read. Special Edition writes 12.
    case unsupportedVersion(UInt32)
    /// A body compression value other than none, zlib, or LZ4.
    case unsupportedCompression(UInt16)
    /// A form version this build does not read.
    case unsupportedFormVersion(UInt8)
    /// The file ends inside `context`.
    case truncated(context: String)
    /// A count cannot fit in the bytes that remain, caught before any allocation.
    case invalidCount(context: String, count: Int)
    /// A field holds a value the format does not define.
    case invalidValue(context: String)
    /// The compressed body did not decode to its declared length.
    case decompressionFailed(context: String)
    /// A file location table offset points outside the body or out of order.
    case sectionOutOfRange(section: String, offset: UInt32)
}

nonisolated extension ESSError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .badMagic: "not a Skyrim save (bad magic)"
        case let .unsupportedVersion(version): "unsupported save version \(version)"
        case let .unsupportedCompression(value): "unsupported compression \(value)"
        case let .unsupportedFormVersion(value): "unsupported form version \(value)"
        case let .truncated(context): "file ends inside \(context)"
        case let .invalidCount(context, count): "\(context) count \(count) is too large"
        case let .invalidValue(context): "invalid value: \(context)"
        case let .decompressionFailed(context): "decompression failed: \(context)"
        case let .sectionOutOfRange(section, offset):
            String(format: "%@ offset 0x%X is out of range", section, offset)
        }
    }
}
