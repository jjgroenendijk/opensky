// The Progression panel's tick: one snapshot per tick shared by all sections,
// never stale after the tick. Split from `ProgressionPanelTests` for the
// type-body cap; the panel comes from that suite's registry factory.

import AppKit
@testable import OpenSky
import Testing

@MainActor
struct ProgressionPanelTickTests {
    /// One panel tick builds the snapshot once and hands the same value to all
    /// three sections.
    @Test
    func onePanelTickBuildsTheSnapshotOnce() throws {
        let providers = FakeWorldProviders()
        providers.progression.snapshot = ProgressionPanelTests.snapshot()
        let panel = try ProgressionPanelTests.panel(providers: providers)
        panel.startInspecting()
        defer { panel.stopInspecting() }

        let before = providers.progression.snapshotReads
        panel.refreshSections()
        #expect(providers.progression.snapshotReads == before + 1)

        // Every section still shows that reading, so the one build reached all
        // three rather than only the section that asked for it.
        for identifier in [
            "ProgressionCharacterStatsLabel",
            "ProgressionSkillsStatsLabel",
            "ProgressionPerkTreeStatsLabel"
        ] {
            let readout = try #require(scriptsReadout(identifier, in: panel.view))
            #expect(!readout.contains("unavailable"))
        }

        // The hand-down does not outlive the tick: a refresh after a button
        // press has to read what the action just changed.
        for section in panel.progressionSections {
            #expect(section.tickSnapshot == nil)
        }
        panel.skillsSection.refreshReadout()
        #expect(providers.progression.snapshotReads == before + 2)
    }
}
