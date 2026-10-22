// World > Progression > Perk Choices: the crosshair target's Activate perk choices, and
// the Run button that runs the selected one.

import AppKit
@testable import OpenSky
import OpenSkyMenus
import Testing

@MainActor
struct PerkActivationPanelTests {
    @Test
    func theSectionCarriesItsIdentifiers() throws {
        let panel = try ProgressionPanelTests.panel(providers: FakeWorldProviders())
        let section = panel.perkChoicesSection
        section.loadViewIfNeeded()
        #expect(section.sectionIdentifier == "perkChoices")
        #expect(section.sectionTitle == "Perk Choices")
        #expect(section.choiceControl.accessibilityIdentifier() == "PerkChoiceSelectControl")
        #expect(section.runControl.accessibilityIdentifier() == "PerkChoiceRunControl")
        #expect(panel.makeSections().last === section)
    }

    @Test
    func anEmptyTargetDisablesTheControls() throws {
        let panel = try ProgressionPanelTests.panel(providers: FakeWorldProviders())
        let section = panel.perkChoicesSection
        section.loadViewIfNeeded()
        section.refreshReadout()
        #expect(!section.runControl.isEnabled)
        #expect(section.readout.contains("Target: none"))
    }

    @Test
    func runSendsTheSelectedRow() throws {
        let providers = FakeWorldProviders()
        providers.progression.perkChoices = PerkActivationSnapshot(
            target: "Bandit",
            rows: [
                .init(label: "Feed", runsImmediately: false, replacesDefault: false),
                .init(label: "Harvest blood", runsImmediately: false, replacesDefault: true)
            ],
            lastRun: nil
        )
        let panel = try ProgressionPanelTests.panel(providers: providers)
        let section = panel.perkChoicesSection
        section.loadViewIfNeeded()
        section.refreshReadout()
        #expect(section.choiceControl.itemTitles == ["Feed", "Harvest blood (replaces)"])
        #expect(section.readout.contains("Target: Bandit"))

        section.choiceControl.selectItem(at: 1)
        sendScriptsControl(section.runControl)
        #expect(providers.progression.perkChoiceRuns == [1])
    }
}
