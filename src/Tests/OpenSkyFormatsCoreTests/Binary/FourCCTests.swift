// FourCC type-code tests.

import Foundation
@testable import OpenSkyFormatsCore
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct FourCCTests {
    @Test func literalMatchesLittleEndianBytes() throws {
        var reader = BinaryReader(Data("TES4".utf8))
        #expect(try reader.readFourCC() == "TES4")
        #expect(FourCC(stringLiteral: "GRUP").rawValue == 0x5055_5247)
    }

    @Test func aLiteralOfTheWrongLengthIsTheInvalidCode() {
        #expect(FourCC(stringLiteral: "ABC") == .invalidLiteral)
        #expect(FourCC(stringLiteral: "WEAPON") == .invalidLiteral)
        #expect(FourCC(stringLiteral: "") == .invalidLiteral)
    }

    @Test func describesPrintableCodesAsText() {
        #expect(FourCC(stringLiteral: "WRLD").description == "WRLD")
        #expect(FourCC(rawValue: 0x0000_0001).description == "0x00000001")
    }

    @Test func codeTextPacksLikeALiteral() {
        let text = String("GRUP")
        #expect(FourCC(code: text) == "GRUP")
        #expect(FourCC(code: "ABC") == .invalidLiteral)
        #expect(FourCC(code: "WEAPON") == .invalidLiteral)
    }

    /// "\u{E9}" is two UTF-8 bytes, C3 A9, so this literal is four bytes long.
    @Test func aLiteralCountsUTF8BytesNotCharacters() {
        #expect(FourCC(stringLiteral: "\u{E9}\u{E9}").rawValue == 0xA9C3_A9C3)
        #expect(FourCC(stringLiteral: "\u{E9}\u{E9}") == FourCC(code: "\u{E9}\u{E9}"))
    }

    @Test func userTextReadsOnlyFourPrintableCharacters() {
        #expect(FourCC(text: "WEAP") == "WEAP")
        #expect(FourCC(text: "NPC_") == "NPC_")
        #expect(FourCC(text: "WEAPON") == nil)
        #expect(FourCC(text: "AB\u{1}D") == nil)
        #expect(FourCC(text: "") == nil)
    }
}
