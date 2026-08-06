// Engine-wide lenient text decode for game data strings. No Bethesda format
// carries an encoding marker and the wild mixes UTF-8 with legacy codepages,
// so: bytes that form valid UTF-8 decode as UTF-8 (accidental valid UTF-8 is
// rare), everything else decodes as windows-1252. Policy discussion in
// docs/formats/strings.md.

import Foundation

nonisolated enum GameText {
    /// Nil only for byte sequences no supported codepage can represent.
    static func decode(_ bytes: Data) -> String? {
        if let utf8 = String(data: bytes, encoding: .utf8) {
            return utf8
        }
        return String(data: bytes, encoding: .windowsCP1252)
    }

    /// Never nil: bytes undefined in windows-1252 fall back to ISO 8859-1,
    /// which maps every byte. For name-ish strings where garbage input must
    /// not reject the whole asset — vanilla NIF string tables carry exporter
    /// junk (uninitialized memory, e.g. 0x90 bytes).
    static func decodeLossy(_ bytes: Data) -> String {
        if let text = decode(bytes) {
            return text
        }
        return String(data: bytes, encoding: .isoLatin1) ?? ""
    }
}
