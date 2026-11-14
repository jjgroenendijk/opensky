// The app start phases of a benchmark result add up to the whole start.

import Foundation
@testable import OpenSkyWorld
import OpenSkyWorldInterface
import Testing

@MainActor
struct AppStartPhaseTests {
    @Test func theAppStartPhasesAddUpToTheWholeStart() {
        let start = Date(timeIntervalSince1970: 1000)
        let marks = AppStartMarks(
            mainEntered: start + 0.5, launchFinished: start + 0.75,
            worldLoadStarted: start + 1, worldLoadFinished: start + 5
        )
        let report = WorldLoadReport(
            timeline: WorldLoadTimeline(),
            total: .seconds(4),
            marks: marks
        )
        var session = SessionStartTiming()
        session.startedAt = start + 6
        session.firstFrameAt = start + 9
        let appStart = BenchmarkAppStart(
            report: report, session: session, processStart: start, worldReady: start + 13
        )
        #expect(appStart.processToWorldReadyMS == 13000)
        #expect(appStart.phases == [
            "beforeMain": 500, "appLaunch": 250, "beforeWorldLoad": 250, "worldLoad": 4000,
            "beforeSession": 1000, "session": 3000, "startArea": 4000
        ])
        #expect(appStart.phases.values.reduce(0, +) == 13000)
    }

    @Test func aMissingMarkLeavesItsPhaseOutAndTheSumWhole() {
        let start = Date(timeIntervalSince1970: 1000)
        let phases = AppStartPhase.split(
            from: start, to: start + 10, ends: [.worldLoad: start + 4, .session: start + 7]
        )
        #expect(phases == [.worldLoad: 4000, .session: 3000, .startArea: 3000])
    }

    @Test func anAppStartWithoutPhasesStillDecodes() throws {
        let json = Data(#"{"worldLoadMS": 1, "stages": {}, "sessionStart": {}}"#.utf8)
        let start = try JSONDecoder().decode(BenchmarkAppStart.self, from: json)
        #expect(start.phases.isEmpty)
    }

    @Test func theSummaryListsThePhasesInOrder() {
        let start = BenchmarkAppStart(
            processToWorldReadyMS: 3, worldLoadMS: 1, stages: [:], sessionStart: [:],
            phases: ["startArea": 2, "worldLoad": 1]
        )
        var result = BenchmarkTourResult(
            startedAt: Date(),
            machine: BenchmarkMachine(
                modelIdentifier: "Mac0,0", cpu: "CPU", gpu: "GPU", logicalCores: 8,
                memoryGB: 16, osVersion: "26.0"
            ),
            preset: .quick
        )
        result.appStart = start
        #expect(BenchmarkReport.lines(for: result).contains(
            "App start phases (ms): worldLoad 1.0, startArea 2.0"
        ))
    }
}
