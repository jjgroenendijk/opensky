// The colour ramp of a gradient: stops spread over the texels, the ends padded, and the
// linear RGB mode mixing in linear light. Fixtures are built in code.

@testable import OpenSkyFormatsSWF
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct SWFGradientRampTests {
    private let red = SWFColor(red: 255, green: 0, blue: 0, alpha: 255)
    private let clearBlue = SWFColor(red: 0, green: 0, blue: 255, alpha: 0)

    private func gradient(
        _ mode: SWFGradient.InterpolationMode, lastRatio: UInt8 = 255
    ) -> SWFGradient {
        SWFGradient(
            spreadMode: .pad, interpolationMode: mode,
            records: [
                SWFGradientRecord(ratio: lastRatio, color: clearBlue),
                SWFGradientRecord(ratio: 0, color: red)
            ],
            focalPoint: nil
        )
    }

    @Test func theEndsAreTheStopsAndTheMiddleMixesStraight() {
        let ramp = gradient(.normalRGB).rampColors(width: 3)
        #expect(ramp.first == red)
        #expect(ramp.last == clearBlue)
        #expect((127 ... 128).contains(ramp[1].red))
        #expect((127 ... 128).contains(ramp[1].blue))
        #expect((127 ... 128).contains(ramp[1].alpha))
    }

    /// Half way in linear light is 0.5, which the sRGB curve stores as 188 of 255.
    @Test func linearRGBMixesTheColourInLinearLightButNotTheAlpha() {
        let middle = gradient(.linearRGB).rampColors(width: 3)[1]
        #expect((187 ... 188).contains(middle.red))
        #expect((187 ... 188).contains(middle.blue))
        #expect((127 ... 128).contains(middle.alpha))
    }

    @Test func pastTheLastStopTheRampKeepsItsColour() {
        let ramp = gradient(.normalRGB, lastRatio: 128).rampColors(width: 256)
        #expect(ramp[200] == clearBlue)
        #expect(ramp[255] == clearBlue)
    }

    @Test func aGradientWithoutStopsIsClear() {
        let empty = SWFGradient(
            spreadMode: .pad, interpolationMode: .normalRGB, records: [], focalPoint: nil
        )
        #expect(empty.rampColors(width: 2).allSatisfy { $0.alpha == 0 })
        #expect(gradient(.normalRGB).rampColors(width: 1) == [red])
    }
}
