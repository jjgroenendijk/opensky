// World > World Load: the readout of the load that built the running session.

import AppKit
@testable import OpenSky
import OpenSkyWorld
import Testing

@MainActor
struct WorldLoadSectionTests {
    private final class FakeProvider: WorldLoadReportProviding {
        var worldLoadReport: WorldLoadReport?
        var sessionStartTiming = SessionStartTiming()
    }

    @Test
    func theSectionIsReachableUnderTheWorldDestination() throws {
        let descriptor = try #require(DestinationRegistry.all.first { $0.id == "world" })
        guard case let .worldInspector(makePanel) = descriptor.content else {
            Issue.record("World is not a world inspector")
            return
        }
        let panel = try #require(
            makePanel(WorldPanelContext(providers: FakeWorldProviders()))
                as? WorldPanelViewController
        )
        panel.loadViewIfNeeded()
        #expect(panel.sections.map(\.sectionIdentifier).contains("worldLoad"))
        #expect(panel.worldLoadSection.statsReadout == "World load: none")
    }

    @Test
    func showsNoneWithoutALoad() {
        let section = WorldLoadSection()
        let provider = FakeProvider()
        section.loadViewIfNeeded()
        section.provider = provider

        #expect(section.statsReadout == "World load: none")
        #expect(section.sectionIdentifier == "worldLoad")
    }

    @Test
    func listsTotalThenStagesSlowestFirst() {
        var timeline = WorldLoadTimeline()
        timeline.apply(WorldLoadEvent(stage: .dialogue, kind: .finished(.milliseconds(1400))))
        timeline.apply(WorldLoadEvent(stage: .items, kind: .finished(.milliseconds(4500))))
        let provider = FakeProvider()
        provider.worldLoadReport = WorldLoadReport(timeline: timeline, total: .milliseconds(4750))
        let section = WorldLoadSection()
        section.loadViewIfNeeded()
        section.provider = provider

        #expect(section.statsReadout == """
        Total: 4.75 s
        Items and inventories: 4.50 s
        Dialogue: 1.40 s
        """)
    }

    @Test
    func listsTheSessionStartPhasesInRunOrderAfterTheStages() {
        var timeline = WorldLoadTimeline()
        timeline.apply(WorldLoadEvent(stage: .items, kind: .finished(.milliseconds(4500))))
        let provider = FakeProvider()
        provider.worldLoadReport = WorldLoadReport(timeline: timeline, total: .milliseconds(4500))
        provider.sessionStartTiming.record(.firstFrame, .milliseconds(120))
        provider.sessionStartTiming.record(.renderer, .milliseconds(50))
        provider.sessionStartTiming.record(.systems, .milliseconds(830))
        let section = WorldLoadSection()
        section.loadViewIfNeeded()
        section.provider = provider

        #expect(section.statsReadout == """
        Total: 4.50 s
        Items and inventories: 4.50 s
        Session start: 1.00 s
        Renderer setup: 0.05 s
        Game systems: 0.83 s
        First frame: 0.12 s
        """)
    }
}
