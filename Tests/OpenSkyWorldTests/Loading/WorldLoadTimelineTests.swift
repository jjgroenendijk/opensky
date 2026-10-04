// Stage bookkeeping of the world load: states, progress fraction, ordering.

@testable import OpenSkyWorld
import Testing

struct WorldLoadTimelineTests {
    @Test
    func startsWithEveryStagePending() {
        let timeline = WorldLoadTimeline()
        #expect(timeline.finishedCount == 0)
        #expect(timeline.fraction == 0)
        #expect(timeline.runningStages.isEmpty)
        #expect(WorldLoadStage.allCases.allSatisfy { timeline.state(of: $0) == .pending })
    }

    @Test
    func tracksRunningAndFinishedStages() {
        var timeline = WorldLoadTimeline()
        timeline.apply(WorldLoadEvent(stage: .packages, kind: .started))
        timeline.apply(WorldLoadEvent(stage: .dialogue, kind: .started))
        timeline.apply(WorldLoadEvent(stage: .dialogue, kind: .finished(.milliseconds(1400))))

        #expect(timeline.runningStages == [.packages])
        #expect(timeline.state(of: .dialogue) == .finished(.milliseconds(1400)))
        #expect(timeline.finishedCount == 1)
        #expect(timeline.fraction == 1 / Double(WorldLoadStage.allCases.count))
    }

    @Test
    func listsFinishedStagesSlowestFirst() {
        var timeline = WorldLoadTimeline()
        timeline.apply(WorldLoadEvent(stage: .settings, kind: .finished(.milliseconds(70))))
        timeline.apply(WorldLoadEvent(stage: .items, kind: .finished(.milliseconds(4500))))
        timeline.apply(WorldLoadEvent(stage: .quests, kind: .finished(.milliseconds(1500))))

        #expect(timeline.slowestFirst.map(\.stage) == [.items, .quests, .settings])
    }

    @Test
    func formatsSecondsWithTwoDecimals() {
        #expect(Duration.milliseconds(1250).secondsText == "1.25 s")
        #expect(Duration.zero.secondsText == "0.00 s")
    }
}
