// The World > Progression skills section's legendary and perk-tree reset buttons.

import AppKit
@testable import OpenSky
import Testing

@MainActor
struct ProgressionLegendaryPanelTests {
    @Test
    func theLegendaryAndResetButtonsKeepTheirIdentifiers() throws {
        let panel = try ProgressionPanelTests.panel(providers: FakeWorldProviders())
        let skills = panel.skillsSection
        #expect(
            skills.legendaryControl.accessibilityIdentifier()
                == "ProgressionLegendarySkillControl"
        )
        #expect(
            skills.resetTreeControl.accessibilityIdentifier()
                == "ProgressionResetPerkTreeControl"
        )
    }

    @Test
    func theLegendaryAndResetButtonsReachTheProvider() throws {
        let providers = FakeWorldProviders()
        let panel = try ProgressionPanelTests.panel(providers: providers)
        sendScriptsControl(panel.skillsSection.legendaryControl)
        sendScriptsControl(panel.skillsSection.resetTreeControl)
        #expect(providers.progression.legendaryCount == 1)
        #expect(providers.progression.resetTreeCount == 1)
    }
}
