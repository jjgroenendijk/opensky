// Lenient text decode for game strings. Valid UTF-8 decodes as UTF-8, anything
// else as windows-1252, with its five undefined bytes as ISO 8859-1. It never
// throws. Policy: docs/decisions/string-decoding.md.

import Foundation

nonisolated public enum GameText: Sendable {
    /// Total: every byte sequence decodes to some string, so a mis-encoded name
    /// degrades to mojibake instead of failing the record, asset, or archive
    /// that carries it.
    public static func decode(_ bytes: Data) -> String {
        if let utf8 = String(data: bytes, encoding: .utf8) {
            return utf8
        }
        if let ansi = String(data: bytes, encoding: .windowsCP1252) {
            return ansi
        }
        // ISO 8859-1 maps all 256 byte values, so this cannot fail; the `?? ""`
        // only satisfies the optional-returning API. Vanilla NIF string tables
        // carry exporter junk (uninitialized memory, e.g. 0x90) that lands here.
        return String(data: bytes, encoding: .isoLatin1) ?? ""
    }
}

/// How a `BinaryReader` string read turns bytes into text.
nonisolated public enum TextDecoding: Equatable, Sendable {
    /// The engine-wide lenient game-data policy (`GameText.decode`). Never fails.
    case gameText
    /// One fixed encoding; bytes outside it throw `BinaryReaderError.invalidString`.
    /// For structural fields whose encoding the format itself pins down, such as
    /// Havok's ASCII type and version names, where garbage means a bad file.
    case strict(String.Encoding)

    /// Nil only for `.strict` when the bytes are not valid in that encoding.
    public func decode(_ bytes: Data) -> String? {
        switch self {
        case .gameText:
            GameText.decode(bytes)
        case let .strict(encoding):
            String(data: bytes, encoding: encoding)
        }
    }
}
