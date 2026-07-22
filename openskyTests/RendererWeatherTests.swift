// Weather renderer integration (M7.2.2): offscreen A/B renders proving the
// weather sky path. No active weather reproduces the procedural baseline
// bit-for-bit; a forced synthetic weather repaints the sky; two distinct
// weathers differ. Synthetic fixtures only (AGENTS.md "Legal & IP boundary");
// skips without a Metal 4 device (paravirtual CI), like RendererShadowTests.

import Foundation
import Metal
import MetalKit
@testable import opensky
import simd
import Testing

struct RendererWeatherTests {
    static var hasMetal4Device: Bool {
        RendererShadowTests.hasMetal4Device
    }

    private static let width = RendererShadowTests.width
    private static let height = RendererShadowTests.height

    /// Sky occupies the top of the frame; compare only those rows.
    private static var skyBand: Int {
        width * 40 * 4
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func inactiveWeatherMatchesProceduralBaseline() throws {
        let device = try #require(RendererShadowTests.device)

        let baseline = try RendererShadowTests.makeRenderer(device: device)
        let baselinePixels = try RendererShadowTests.readPixels(
            texture: baseline.renderOffscreen(width: Self.width, height: Self.height)
        )

        // A weather system pinned to a worldspace with no candidates resolves
        // to nil -> the sky must be byte-identical to the never-weather render.
        let withInactive = try RendererShadowTests.makeRenderer(device: device)
        withInactive.weather = try WeatherSystem(store: Self.store(), worldspaceFormID: 0x999)
        let inactivePixels = try RendererShadowTests.readPixels(
            texture: withInactive.renderOffscreen(width: Self.width, height: Self.height)
        )

        var differences = 0
        for index in baselinePixels.indices where baselinePixels[index] != inactivePixels[index] {
            differences += 1
        }
        #expect(differences == 0, "inactive weather changed \(differences) pixels vs baseline")
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func forcedWeatherRepaintsSky() throws {
        let device = try #require(RendererShadowTests.device)

        let baseline = try RendererShadowTests.makeRenderer(device: device)
        let baselinePixels = try RendererShadowTests.readPixels(
            texture: baseline.renderOffscreen(width: Self.width, height: Self.height)
        )

        let forced = try RendererShadowTests.makeRenderer(device: device)
        forced.weather = try WeatherSystem(store: Self.store(), worldspaceFormID: 0x500)
        forced.weather?.forceWeather(FormID(0x100), transition: .instant)
        let forcedPixels = try RendererShadowTests.readPixels(
            texture: forced.renderOffscreen(width: Self.width, height: Self.height)
        )

        var skyDifferences = 0
        for index in 0 ..< Self.skyBand where baselinePixels[index] != forcedPixels[index] {
            skyDifferences += 1
        }
        #expect(skyDifferences > 100, "forced weather left the sky unchanged (\(skyDifferences))")
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func disabledWeatherRestoresProceduralSkyAndCalmWind() throws {
        let device = try #require(RendererShadowTests.device)
        let renderer = try RendererShadowTests.makeRenderer(device: device)
        renderer.weather = try WeatherSystem(store: Self.store(), worldspaceFormID: 0x500)
        renderer.weather?.forceWeather(FormID(0x100), transition: .instant)
        let active = try RendererShadowTests.readPixels(
            texture: renderer.renderOffscreen(width: Self.width, height: Self.height)
        )
        renderer.weatherEnabled = false
        let disabled = try RendererShadowTests.readPixels(
            texture: renderer.renderOffscreen(width: Self.width, height: Self.height)
        )
        #expect(active != disabled)
        #expect(renderer.currentResolvedWeather == nil)
        #expect(renderer.currentWind == .calm)
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func twoWeathersProduceDifferentSkies() throws {
        let device = try #require(RendererShadowTests.device)

        func skyPixels(weather: UInt32) throws -> [UInt8] {
            let renderer = try RendererShadowTests.makeRenderer(device: device)
            renderer.weather = try WeatherSystem(store: Self.store(), worldspaceFormID: 0x500)
            renderer.weather?.forceWeather(FormID(weather), transition: .instant)
            return try RendererShadowTests.readPixels(
                texture: renderer.renderOffscreen(width: Self.width, height: Self.height)
            )
        }

        let blue = try skyPixels(weather: 0x100)
        let red = try skyPixels(weather: 0x200)
        var differences = 0
        for index in 0 ..< Self.skyBand where blue[index] != red[index] {
            differences += 1
        }
        #expect(differences > 100, "distinct weathers rendered the same sky (\(differences))")
    }

    // MARK: - Fixtures

    private static func store() throws -> WeatherStore {
        try WeatherStore(file: ESMFile(data: plugin()))
    }

    /// Two weathers with distinct bright sky palettes + a worldspace/climate.
    private static func plugin() -> Data {
        let weathers = ESMFixture.topGroup(
            "WTHR",
            contents: weather(formID: 0x100, sky: SIMD3(0, 0, 255))
                + weather(formID: 0x200, sky: SIMD3(255, 0, 0))
        )
        let climates = ESMFixture.topGroup(
            "CLMT",
            contents: climate(formID: 0x300)
        )
        let worlds = ESMFixture.topGroup(
            "WRLD",
            contents: worldspace(formID: 0x500, climate: 0x300)
        )
        return ESMFixture.tes4() + weathers + climates + worlds
    }

    /// WTHR with sky-upper/sky-lower/horizon set to one bright color at every
    /// time of day, so the whole sky band takes that hue.
    private static func weather(formID: UInt32, sky: SIMD3<UInt8>) -> Data {
        var nam0 = Data()
        for index in 0 ..< 17 {
            // Components 0 sky-upper, 7 sky-lower, 8 horizon carry the color.
            if index == 0 || index == 7 || index == 8 {
                for _ in 0 ..< 4 {
                    nam0.append(contentsOf: [sky.x, sky.y, sky.z, 0])
                }
            } else {
                nam0.append(Data(count: 16))
            }
        }
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("WTHR\(formID)"))
            + ESMFixture.field("NAM0", nam0)
        return ESMFixture.record("WTHR", formID: formID, data: fields)
    }

    private static func climate(formID: UInt32) -> Data {
        var wlst = Data()
        for weather: UInt32 in [0x100, 0x200] {
            wlst.appendUInt32(weather)
            wlst.appendUInt32(50)
            wlst.appendUInt32(0)
        }
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("CLMT"))
            + ESMFixture.field("WLST", wlst)
        return ESMFixture.record("CLMT", formID: formID, data: fields)
    }

    private static func worldspace(formID: UInt32, climate: UInt32) -> Data {
        var cnam = Data()
        cnam.appendUInt32(climate)
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("TestWorld"))
            + ESMFixture.field("CNAM", cnam)
        return ESMFixture.record("WRLD", formID: formID, data: fields)
    }
}
