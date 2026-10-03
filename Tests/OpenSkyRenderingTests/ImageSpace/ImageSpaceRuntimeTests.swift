// The image-space baseline resolve, the IMAD sampler, and the modifier runtime
// over synthetic IMGS and IMAD records.

import FormatsESMTesting
import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyRendering
import Testing

struct ImageSpaceRuntimeTests {
    private typealias Fixture = ESMFixture
    static let bright = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x10)
    static let dark = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x11)
    static let flash = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x20)

    static func imageSpace(_ name: String, brightness: Float) throws -> ImageSpace {
        try ImageSpace(record: Fixture.record("IMGS", fields: [
            ("EDID", Fixture.zstring(name)),
            ("CNAM", Fixture.f32(1, brightness, 1))
        ]))
    }

    /// An animatable two-second modifier that doubles brightness by its end.
    static func brightnessRamp() throws -> ImageSpaceAdapter {
        var header = Fixture.u32(1) + Fixture.f32(2)
        header += Fixture.words(Array(repeating: 0, count: 42))
        header += Fixture.u32(0)
        header += Fixture.u32(0, 0, 0, 0, 0) + Fixture.u32(0) + Fixture.f32(0, 0)
        header += Fixture.u32(0, 0, 0) + Fixture.u8(0, 0, 0, 0) + Fixture.u32(0, 0, 0, 0)
        return try ImageSpaceAdapter(record: Fixture.record("IMAD", fields: [
            ("EDID", Fixture.zstring("FlashRamp")),
            ("DNAM", header),
            ("\u{12}IAD", Fixture.f32(0, 1, 1, 2))
        ]))
    }

    @Test func anInteriorTakesItsCellImageSpace() throws {
        let space = try Self.imageSpace("Cave", brightness: 0.5)
        let baseline = BaselineImageSpaceResolver
            .resolve(.interior(cellImageSpace: FormID(0x10))) { _ in
                ResolvedImageSpace(key: Self.bright, record: space)
            }
        #expect(baseline.parameters.brightness == 0.5)
        #expect(baseline.dominantName == "Cave")
    }

    @Test func anExteriorBlendsWeathersByWeight() throws {
        let bright = try Self.imageSpace("Bright", brightness: 2)
        let dark = try Self.imageSpace("Dark", brightness: 1)
        let slots = TimeOfDayValues<FormID?>(
            sunrise: FormID(0x10), day: FormID(0x10), sunset: FormID(0x10), night: FormID(0x10)
        )
        let other = TimeOfDayValues<FormID?>(
            sunrise: FormID(0x11), day: FormID(0x11), sunset: FormID(0x11), night: FormID(0x11)
        )
        let context = ImageSpaceContext.exterior(
            weathers: [
                WeightedWeatherImageSpaces(imageSpaces: slots, weight: 0.25),
                WeightedWeatherImageSpaces(imageSpaces: other, weight: 0.75)
            ],
            timeOfDay: TimeOfDayWeights(sunrise: 0, day: 1, sunset: 0, night: 0)
        )
        let baseline = BaselineImageSpaceResolver.resolve(context) { id in
            id == FormID(0x10) ? ResolvedImageSpace(key: Self.bright, record: bright)
                : ResolvedImageSpace(key: Self.dark, record: dark)
        }
        #expect(abs(baseline.parameters.brightness - 1.25) < 0.0001)
        #expect(baseline.dominantName == "Dark")
    }

    @Test func noContextIsNeutral() {
        let baseline = BaselineImageSpaceResolver.resolve(.none) { _ in nil }
        #expect(baseline.parameters.isNeutral)
    }

    @Test func theSamplerReadsFractionKeysOverTheDuration() throws {
        let adapter = try Self.brightnessRamp()
        let middle = adapter.sample(elapsed: 1)
        #expect(abs((middle.values[.cinematic(index: 1, add: false)] ?? 0) - 1.5) < 0.0001)
        #expect(!middle.isFinished)
        #expect(adapter.sample(elapsed: 2.5).isFinished)
        #expect(!adapter.sample(elapsed: 2.5, looping: true).isFinished)
    }

    @Test func aModifierScalesByStrengthAndExpires() throws {
        var runtime = ImageSpaceModifierRuntime()
        try runtime.start(Self.brightnessRamp(), key: Self.flash, strength: 0.5)
        runtime.advance(1)
        let applied = runtime.apply(to: .neutral)
        #expect(abs(applied.brightness - 1.25) < 0.0001)
        runtime.advance(2)
        #expect(runtime.instances.isEmpty)
    }

    @Test func aRepeatedOneShotRestartsInsteadOfStacking() throws {
        var runtime = ImageSpaceModifierRuntime()
        let adapter = try Self.brightnessRamp()
        runtime.start(adapter, key: Self.flash)
        runtime.advance(1)
        runtime.start(adapter, key: Self.flash)
        #expect(runtime.instances.count == 1)
        #expect(runtime.instances[0].elapsed == 0)
    }

    @Test func theForcedBaselineWinsOverTheResolvedOne() throws {
        var state = ImageSpaceState()
        state.forcedBaseline = try ResolvedImageSpace(
            key: Self.dark, record: Self.imageSpace("Tint", brightness: 3)
        )
        #expect(state.current.brightness == 3)
    }
}
