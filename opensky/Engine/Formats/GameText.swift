// Engine-wide lenient text decode for game data strings. No Bethesda format
// carries an encoding marker and the wild mixes UTF-8 with legacy codepages,
// so: bytes that form valid UTF-8 decode as UTF-8 (accidental valid UTF-8 is
// rare), everything else decodes as windows-1252, and the five bytes windows-1252
// leaves undefined decode as ISO 8859-1. The result is total — a wrong-encoding
// name yields mojibake, never a thrown error. Policy in
// docs/decisions/string-decoding.md.

import Foundation

nonisolated enum GameText {
    /// Total: every byte sequence decodes to some string, so a mis-encoded name
    /// degrades to mojibake instead of failing the record, asset, or archive
    /// that carries it.
    static func decode(_ bytes: Data) -> String {
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
nonisolated enum TextDecoding: Equatable {
    /// The engine-wide lenient game-data policy (`GameText.decode`). Never fails.
    case gameText
    /// One fixed encoding; bytes outside it throw `BinaryReaderError.invalidString`.
    /// For structural fields whose encoding the format itself pins down, such as
    /// Havok's ASCII type and version names, where garbage means a bad file.
    case strict(String.Encoding)

    /// Nil only for `.strict` when the bytes are not valid in that encoding.
    func decode(_ bytes: Data) -> String? {
        switch self {
        case .gameText:
            GameText.decode(bytes)
        case let .strict(encoding):
            String(data: bytes, encoding: encoding)
        }
    }
}
