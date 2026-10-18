// The numbers a result reports, its JSON round trip, and its text summary.

import Foundation
@testable import OpenSkyWorld
import Testing

struct BenchmarkResultTests {
    private static let machine = BenchmarkMachine(
        modelIdentifier: "Mac0,0", cpu: "Test CPU", gpu: "Test GPU", logicalCores: 8,
        memoryGB: 16, osVersion: "26.0"
    )

    @Test func theDistributionReportsPercentilesAndTheOnePercentLow() throws {
        let frames = Array(repeating: 10.0, count: 99) + [50]
        let distribution = try #require(BenchmarkDistribution(milliseconds: frames))
        #expect(distribution.frames == 100)
        #expect(distribution.percentile50MS == 10)
        #expect(distribution.percentile99MS == 10)
        #expect(distribution.worstMS == 50)
        #expect(abs(distribution.averageMS - 10.4) < 1e-9)
        #expect(distribution.onePercentLowFPS == 20, "the slowest frame alone, at 50 ms")
        #expect(BenchmarkDistribution(milliseconds: []) == nil)
    }

    @Test func aResultSurvivesItsJSON() throws {
        let scene = try #require(BenchmarkTour.scene(id: "whiterun"))
        var measured = BenchmarkSceneResult(scene: scene, status: .measured)
        measured.frameTime = BenchmarkDistribution(milliseconds: [16, 17, 18])
        measured.passes = try ["scene": #require(BenchmarkSpread(milliseconds: [4, 5]))]
        var result = BenchmarkTourResult(
            startedAt: Date(timeIntervalSince1970: 1_800_000_000), machine: Self.machine,
            preset: .quick
        )
        result.scenes = [measured]
        result.overrides = ["rendering.renderScale": 1]
        let decoded = try BenchmarkTourResult.decode(json: result.jsonData())
        #expect(decoded == result)
        #expect(decoded.schemaVersion == BenchmarkTourResult.currentSchemaVersion)
        #expect(decoded.scenes.first?.slowestPass?.name == "scene")
    }

    @Test func aFailedOrStoppedRunDoesNotCompare() throws {
        let scene = try #require(BenchmarkTour.scene(id: "riften"))
        var result = BenchmarkTourResult(
            startedAt: Date(),
            machine: Self.machine,
            preset: .standard
        )
        result.scenes = [BenchmarkSceneResult(scene: scene, status: .skipped, note: "no plugin")]
        #expect(result.isComparable)
        result.stopped = true
        #expect(!result.isComparable)
        result.stopped = false
        result.scenes.append(BenchmarkSceneResult(scene: scene, status: .failed, note: "timeout"))
        #expect(!result.isComparable)
    }

    @Test func theSummaryHasOneLinePerScene() throws {
        let whiterun = try #require(BenchmarkTour.scene(id: "whiterun"))
        let vale = try #require(BenchmarkTour.scene(id: "forgottenVale"))
        var measured = BenchmarkSceneResult(scene: whiterun, status: .measured)
        measured.frameTime = BenchmarkDistribution(milliseconds: [16, 16, 20])
        measured.arrivalMS = 4200
        var result = BenchmarkTourResult(startedAt: Date(), machine: Self.machine, preset: .full)
        result.scenes = [
            measured,
            BenchmarkSceneResult(scene: vale, status: .skipped, note: "needs Dawnguard.esm")
        ]
        result.frameTime = measured.frameTime
        let lines = BenchmarkReport.lines(for: result)
        #expect(lines.first?.hasPrefix("OpenSky benchmark: Full") == true)
        #expect(lines.contains { $0.hasPrefix("All scenes: ") })
        #expect(lines.contains { $0.contains("Whiterun") && $0.contains("arrival 4.2 s") })
        #expect(lines.contains { $0.contains("skipped: needs Dawnguard.esm") })
    }

    @Test func theNewestRunFolderWins() throws {
        let parent = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: parent) }
        let old = BenchmarkTourResult(
            startedAt: Date(timeIntervalSince1970: 1),
            machine: Self.machine,
            preset: .quick
        )
        let new = BenchmarkTourResult(
            startedAt: Date(timeIntervalSince1970: 2),
            machine: Self.machine,
            preset: .full
        )
        try BenchmarkReport.write(old, to: parent.appending(path: "20260101T000000Z"))
        try BenchmarkReport.write(new, to: parent.appending(path: "20260102T000000Z"))
        try FileManager.default.createDirectory(
            at: parent.appending(path: "20260103T000000Z"),
            withIntermediateDirectories: true
        )
        #expect(BenchmarkReport.latestRun(in: parent)?.result.preset == .full)
        #expect(FileManager.default.fileExists(
            atPath: parent.appending(path: "20260102T000000Z/summary.txt")
                .path(percentEncoded: false)
        ))
    }
}
