// Synthetic translation-file builder shared by the translation-strings tests.
// Fixtures are encoded in code — never extracted game files (AGENTS.md "Legal &
// IP boundary"). Layout follows the Creation Kit / SkyUI translation-file spec;
// see docs/formats/translation-strings.md.

import Foundation

enum TranslationFileFixture {
    /// Encodes `$key<TAB>value` pairs as a translation file, one pair per line.
    static func file(
        _ pairs: [(key: String, value: String)],
        bom: Bool = true,
        lineEnding: String = "\r\n",
        bigEndian: Bool = false
    ) -> Data {
        let body = pairs
            .map { "\($0.key)\t\($0.value)" }
            .joined(separator: lineEnding) + lineEnding
        return encode(body, bom: bom, bigEndian: bigEndian)
    }

    /// Encodes arbitrary text as UTF-16 with an optional BOM. Lets a test build
    /// deliberately malformed input (missing tab, stray lines, odd bytes).
    static func encode(_ text: String, bom: Bool = true, bigEndian: Bool = false) -> Data {
        var data = Data()
        if bom {
            data.append(contentsOf: bigEndian ? [0xFE, 0xFF] : [0xFF, 0xFE])
        }
        for unit in text.utf16 {
            let bytes: [UInt8] = bigEndian
                ? [UInt8(unit >> 8), UInt8(unit & 0xFF)]
                : [UInt8(unit & 0xFF), UInt8(unit >> 8)]
            data.append(contentsOf: bytes)
        }
        return data
    }
}
