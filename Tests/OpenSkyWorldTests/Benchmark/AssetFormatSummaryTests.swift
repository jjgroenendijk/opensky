// Totals per candidate and the preset rule, over hand-built measurements.

import Foundation
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import Testing

struct AssetFormatSummaryTests {
    private static func row(
        _ candidate: String,
        totalMS: Double,
        memory: Int,
        psnr: Double? = nil,
        storage: AssetFileStorage? = .raw
    ) -> AssetCandidateMeasurement {
        let image = psnr.map { value in
            TextureImageDifference(rgbPSNR: value, alphaPSNR: 100, maxChannelError: 9)
        }
        return AssetCandidateMeasurement(
            candidate: candidate, storage: candidate == "original" ? nil : storage,
            path: candidate == "original" ? .archive : .cpu,
            timing: AssetLoadTiming(readMS: totalMS, decodeMS: 0, uploadMS: 0),
            sizes: (memory, memory),
            fidelity: AssetFidelity(exact: psnr == nil, image: image)
        )
    }

    private static func texture(_ rows: [AssetCandidateMeasurement]) -> AssetMeasurement {
        AssetMeasurement(
            entry: AssetSampleEntry(path: "textures\\a.dds", kind: .texture, role: .color),
            detail: "", candidates: rows
        )
    }

    private static let assets = [
        texture([
            row("original", totalMS: 10, memory: 100),
            row("shipped", totalMS: 4, memory: 100),
            row("rgba8", totalMS: 3, memory: 400),
            row("astc8x8", totalMS: 2, memory: 25, psnr: 35),
            row("astc4x4", totalMS: 2.5, memory: 100, psnr: 45)
        ]),
        texture([
            row("original", totalMS: 20, memory: 200),
            row("shipped", totalMS: 8, memory: 200),
            row("rgba8", totalMS: 6, memory: 800),
            row("astc8x8", totalMS: 4, memory: 50, psnr: 33),
            row("astc4x4", totalMS: 5, memory: 200, psnr: 41)
        ])
    ]

    @Test func summariesAddUpEachCandidate() throws {
        let summaries = AssetFormatSummary.summarize(Self.assets)
        let astc = try #require(summaries.first { $0.group.candidate == "astc8x8" })
        #expect(astc.assetCount == 2)
        #expect(astc.timing.totalMS == 6)
        #expect(astc.memoryBytes == 75)
        #expect(astc.worstRGBPSNR == 33)
        #expect(!astc.allExact)
    }

    @Test func presetsPickByTheirRule() {
        let picks = AssetFormatRecommendation.recommend(AssetFormatSummary.summarize(Self.assets))
        let choice = { (preset: AssetQualityPreset) in
            picks.first { $0.preset == preset }?.choice.candidate
        }
        // Exact only, fastest: RGBA8 beats the shipped blocks on time.
        #expect(choice(.highestQuality) == "rgba8")
        // Least memory within 40 dB: ASTC 4x4 ties the original and loads faster.
        #expect(choice(.balanced) == "astc4x4")
        // Least memory within 30 dB.
        #expect(choice(.bestPerformance) == "astc8x8")
    }

    @Test func aFailedRowRulesTheCandidateOut() {
        var assets = Self.assets
        var failing = Self.row("astc8x8", totalMS: 1, memory: 1, psnr: 50)
        failing = AssetCandidateMeasurement(
            candidate: failing.candidate, storage: failing.storage, path: failing.path,
            timing: failing.timing, sizes: (1, 1), fidelity: failing.fidelity, error: "boom"
        )
        assets.append(Self.texture([Self.row("original", totalMS: 1, memory: 1), failing]))
        let picks = AssetFormatRecommendation.recommend(AssetFormatSummary.summarize(assets))
        #expect(!picks.contains { $0.choice.candidate == "astc8x8" })
    }

    @Test func resultRoundTripsThroughJSON() throws {
        let result = AssetFormatComparisonResult(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            machine: BenchmarkMachine(
                modelIdentifier: "Mac", cpu: "M", gpu: "G", logicalCores: 8,
                memoryGB: 16, osVersion: "26"
            ),
            loadAverage: [1, 2],
            plan: AssetFormatComparisonPlan(entries: [], repeats: 1),
            assets: Self.assets
        )
        #expect(try AssetFormatComparisonResult.decode(json: result.jsonData()) == result)
    }

    @Test func signalToNoiseIsNilOnlyForIdenticalSamples() throws {
        #expect(AssetFormatComparison
            .signalToNoise(reference: [0.5, -0.5], candidate: [0.5, -0.5]) == nil)
        let noise = try #require(
            AssetFormatComparison.signalToNoise(reference: [1, -1], candidate: [0.5, -1])
        )
        // Signal 2, noise 0.25: 9 dB.
        #expect(abs(noise - 10 * log10(8)) < 1e-6)
    }

    @Test func standardPlanCoversEveryKind() {
        let kinds = Set(AssetFormatComparisonPlan.standard.entries.map(\.kind))
        #expect(kinds == Set(AssetKind.allCases))
        let roles = Set(AssetFormatComparisonPlan.standard.entries.compactMap(\.role))
        #expect(roles == Set(TextureRole.allCases))
    }
}
