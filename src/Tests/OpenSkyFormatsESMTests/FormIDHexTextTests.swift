// A FormID typed by a person: hexadecimal, with or without a 0x prefix.

@testable import OpenSkyFormatsESM
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct FormIDHexTextTests {
    @Test
    func readsHexWithAndWithoutPrefix() {
        #expect(FormID(hexText: "0x00012E49")?.rawValue == 0x12E49)
        #expect(FormID(hexText: "0X14") == .playerReference)
        #expect(FormID(hexText: "12e49")?.rawValue == 0x12E49)
    }

    @Test
    func rejectsWhatIsNotHex() {
        #expect(FormID(hexText: "player") == nil)
        #expect(FormID(hexText: "0x") == nil)
        #expect(FormID(hexText: "1_0000_0000") == nil)
    }
}
