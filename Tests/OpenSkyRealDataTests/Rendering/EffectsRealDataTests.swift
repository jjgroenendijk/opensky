// Env-gated checks of the effect runtimes against the user's install: the
// baseline image space of the clear weathers, every IMAD sampled over its
// playback time, and the rain and snow SPGD read into precipitation scales.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyRendering
import Testing

struct EffectsRealDataTests {
    private static let plugin = "Skyrim.esm"

    private static func load() throws -> (ESMFile, EffectRecordStore) {
        let root = try #require(RealDataEnvironment.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: plugin))
        return (file, EffectRecordStore(plugins: [(name: plugin, file: file)]))
    }

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func everyWeatherResolvesABaselineImageSpace() throws {
        let (file, records) = try Self.load()
        let weathers = WeatherStore(file: file).weathers.values
        var resolved = 0
        for weather in weathers {
            let context = ImageSpaceContext.exterior(
                weathers: [WeightedWeatherImageSpaces(
                    imageSpaces: weather.sky.imageSpaces,
                    weight: 1
                )],
                timeOfDay: TimeOfDayWeights(sunrise: 0, day: 1, sunset: 0, night: 0)
            )
            let baseline = BaselineImageSpaceResolver.resolve(context) { id in
                records.imageSpaces.resolve(id, fromPlugin: Self.plugin).map {
                    ResolvedImageSpace(key: ReferenceKey(resolved: $0.id), record: $0.record)
                }
            }
            let values = baseline.parameters
            #expect(values.saturation.isFinite && values.brightness.isFinite && values.contrast
                .isFinite)
            if baseline.dominantName != "none" {
                resolved += 1
            }
        }
        print("[INFO] \(resolved) of \(weathers.count) weathers resolve a day image space")
        #expect(resolved > weathers.count / 2, "most weathers should name a day image space")
    }

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func everyModifierSamplesFiniteAndFinishes() throws {
        let (_, records) = try Self.load()
        let adapters = records.imageSpaceAdapters.records.map(\.record)
        try #require(!adapters.isEmpty)
        for adapter in adapters {
            let total = adapter.playbackDuration
            for time in [0, total / 2, total] {
                let sample = adapter.sample(elapsed: time)
                let finite = sample.values.values.allSatisfy(\.isFinite)
                #expect(finite, "\(adapter.editorID ?? "?") at \(time)")
                #expect(!sample.isFinished)
            }
            #expect(adapter.sample(elapsed: total + 0.01).isFinished)
            let applied = ImageSpaceParameters.neutral.applying(
                adapter.sample(elapsed: total / 2),
                strength: 1
            )
            #expect(applied.clampedForDisplay.brightness.isFinite)
        }
        print("[INFO] \(adapters.count) IMAD sampled at start, middle, and end")
    }

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func rainAndSnowRecordsGivePlausibleScales() throws {
        let (_, records) = try Self.load()
        let rain = try #require(records.shaderParticles.record(editorID: "RainParticles")?.record)
        let rainTuning = PrecipitationTuning(record: rain)
        #expect(rainTuning.source == "RainParticles")
        #expect(abs(rainTuning.rain.speed - 1) < 0.01)
        #expect(abs(rainTuning.rain.size - 1) < 0.01)
        #expect(rainTuning.snow == .identity)
        let snow = try #require(records.shaderParticles.record(editorID: "SnowParticlesMed")?
            .record)
        #expect(abs(PrecipitationTuning(record: snow).snow.density - 1) < 0.01)
        for geometry in records.shaderParticles.records.map(\.record) {
            let tuning = PrecipitationTuning(record: geometry)
            for scale in [tuning.rain, tuning.snow] {
                #expect(PrecipitationScale.range.contains(scale.speed))
                #expect(PrecipitationScale.range.contains(scale.size))
            }
            print(
                "[INFO] \(tuning.source ?? "fallback"): "
                    + tuning.readoutLines.dropFirst().joined(separator: " | ")
            )
        }
    }
}
