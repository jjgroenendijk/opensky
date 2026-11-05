// The weather's VOLI links blended into the volumetric light values.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyRenderCore
import Testing

struct VolumetricLightValuesTests {
    private typealias Fixture = ESMFixture

    static func record(intensity: Float, scattering: Float) throws -> VolumetricLighting {
        try VolumetricLighting(record: Fixture.record("VOLI", fields: [
            ("CNAM", Fixture.f32(intensity)), ("DNAM", Fixture.f32(0.5)),
            ("ENAM", Fixture.f32(1)), ("FNAM", Fixture.f32(0)), ("GNAM", Fixture.f32(0)),
            ("MNAM", Fixture.f32(scattering)), ("NNAM", Fixture.f32(20))
        ]))
    }

    @Test func theRecordReplacesOnlyItsFields() throws {
        let values = try VolumetricLightValues(Self.record(intensity: 4, scattering: 0.8))
        #expect(values.intensity == 4)
        #expect(values.customColorContribution == 0.5)
        #expect(values.color == SIMD3(1, 0, 0))
        #expect(values.samplingRangeFactor == 20)
        #expect(values.densitySize == VolumetricLightValues.fallback.densitySize)
    }

    @Test func theTimeOfDaySlotsBlend() throws {
        let dawn = try Self.record(intensity: 1, scattering: 0.7)
        let noon = try Self.record(intensity: 3, scattering: 0.9)
        let links = TimeOfDayValues<FormID?>(
            sunrise: FormID(1), day: FormID(2), sunset: nil, night: nil
        )
        let values = VolumetricLightValues.resolve(
            weathers: [(links: links, weight: 1)],
            timeOfDay: TimeOfDayWeights(sunrise: 0.5, day: 0.5, sunset: 0, night: 0)
        ) { $0.rawValue == 1 ? dawn : $0.rawValue == 2 ? noon : nil }
        #expect(abs(values.intensity - 2) < 1e-5)
        #expect(abs(values.phaseFunctionScattering - 0.8) < 1e-5)
    }

    @Test func noWeatherFallsBack() {
        let values = VolumetricLightValues.resolve(
            weathers: [], timeOfDay: TimeOfDayWeights(sunrise: 0, day: 1, sunset: 0, night: 0)
        ) { _ in nil }
        #expect(values == .fallback)
        var wild = VolumetricLightValues()
        wild.phaseFunctionScattering = 3
        wild.densityContribution = .nan
        #expect(wild.clamped.phaseFunctionScattering == 0.95)
        #expect(wild.clamped.densityContribution == 0)
    }
}
