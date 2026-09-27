// FourCC type-code tests.

import Foundation
@testable import opensky
import Testing

struct FourCCTests {
    @Test func literalMatchesLittleEndianBytes() throws {
        var reader = BinaryReader(Data("TES4".utf8))
        #expect(try reader.readFourCC() == "TES4")
        #expect(FourCC(stringLiteral: "GRUP").rawValue == 0x5055_5247)
    }

    @Test func describesPrintableCodesAsText() {
        #expect(FourCC(stringLiteral: "WRLD").description == "WRLD")
        #expect(FourCC(rawValue: 0x0000_0001).description == "0x00000001")
    }
}
