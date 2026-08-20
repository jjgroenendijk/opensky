// The Progression panel's tick discipline (issue #556): one snapshot per tick,
// shared by all three sections, and not a stale value once the tick is over.
//
// Split from `ProgressionPanelTests` — the geometry, the identifiers and the
// controls — because the two together are past the type-body cap. The panel
// itself is built through that suite's registry factory, so what is under test
// is the destination a user clicks.

import AppKit
@testable import opensky
import Testing

@MainActor
struct ProgressionPanelTickTests {
    /// One panel tick builds the snapshot once and hands the same value to all
    /// three sections (issue #556). Left to their own tickers they built it
    /// three times per tick for one identical reading.
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
