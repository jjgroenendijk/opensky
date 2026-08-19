// The Actor Values section's "Other value" field (issue #468, roadmap item
// 19.5), split out of `CombatPhysicsPanelTests` because that suite is at its
// size shape.
//
// The panel and the fake provider are that suite's: what is under test is which
// actor-value index the section sends, not how the panel is built.

import AppKit
@testable import opensky
import Testing

@MainActor
struct CombatActorValuesPanelTests {
    /// Item 19.5: the typed name wins over the popup, by vanilla name and by
    /// bare index, and something that names no actor value falls back to the
    /// popup rather than acting on a guess.
    @Test @MainActor
    func theOtherValueFieldSelectsAnyActorValue() throws {
        let providers = FakeWorldProviders()
        let panel = try CombatPhysicsPanelTests.panel(providers: providers)
        let section = panel.actorValuesSection

        section.valueNameControl.stringValue = "Resist Fire"
        section.amountControl.stringValue = "60"
        sendScriptsControl(section.setControl)
        #expect(providers.actorValues.sets.last?.index == 41)
        #expect(providers.actorValues.sets.last?.value == 60)

        // Papyrus's spelling of the same name, and the bare index.
        section.valueNameControl.stringValue = "ResistFrost"
        sendScriptsControl(panel.damageControl)
        #expect(providers.actorValueSelection == 43)
        section.valueNameControl.stringValue = "15"
        sendScriptsControl(panel.damageControl)
        #expect(providers.actorValueSelection == 15)

        // Neither a vanilla name nor an index in the table: the popup wins.
        section.valueNameControl.stringValue = "Wabbajack"
        section.kindControl.selectItem(at: 1)
        sendScriptsControl(panel.damageControl)
        #expect(providers.actorValueSelection == 25)
    }

    /// Item 20.3: "Set base" sends the same selection the other buttons send
    /// and lands on the base write rather than on the current-value one, which
    /// is the difference the whole store exists for.
    @Test @MainActor
    func theSetBaseControlWritesTheBaseOfTheSelectedValue() throws {
        let providers = FakeWorldProviders()
        let panel = try CombatPhysicsPanelTests.panel(providers: providers)
        let section = panel.actorValuesSection

        section.amountControl.stringValue = "150"
        sendScriptsControl(section.setBaseControl)
        // Health, which the popup starts on.
        #expect(providers.actorValues.baseSets.last?.index == 24)
        #expect(providers.actorValues.baseSets.last?.value == 150)
        #expect(providers.actorValues.sets.isEmpty)

        section.valueNameControl.stringValue = "Sneak"
        section.amountControl.stringValue = "30"
        sendScriptsControl(section.setBaseControl)
        #expect(providers.actorValues.baseSets.last?.index == 15)
        #expect(providers.actorValues.baseSets.last?.value == 30)
    }

    @Test @MainActor
    func withNoRuntimeTheActorValueSectionSaysSo() throws {
        // The fake is bound rather than passed inline: the section holds its
        // provider weakly, so a discarded one would be reporting a missing
        // provider instead of the unavailable snapshot this case is about.
        let providers = FakeWorldProviders()
        let panel = try CombatPhysicsPanelTests.panel(providers: providers)
        panel.startInspecting()
        defer { panel.stopInspecting() }
        let readout = try #require(
            scriptsReadout("CombatActorValuesStatsLabel", in: panel.view)
        )
        #expect(readout.contains("Player: unavailable"))
    }

    /// The two buttons send the value the popup selected and the amount the
    /// field holds, rather than a default either of them invented.
    @Test @MainActor
    func theDamageControlsSendTheSelectedValueAndTypedAmount() throws {
        let providers = FakeWorldProviders()
        let panel = try CombatPhysicsPanelTests.panel(providers: providers)
        let section = panel.actorValuesSection

        section.targetControl.selectItem(at: 1)
        sendScriptsControl(section.targetControl)
        #expect(providers.actorValueTarget == .nearestActor)

        section.kindControl.selectItem(at: 2)
        section.amountControl.stringValue = "42.5"
        sendScriptsControl(panel.damageControl)
        #expect(providers.actorValues.damages.last?.kind == .stamina)
        #expect(providers.actorValues.damages.last?.amount == 42.5)

        section.kindControl.selectItem(at: 1)
        sendScriptsControl(section.restoreControl)
        #expect(providers.actorValues.restores.last?.kind == .magicka)

        sendScriptsControl(section.refillControl)
        #expect(providers.actorValues.refillCount == 1)
        sendScriptsControl(section.resetControl)
        #expect(providers.actorValues.resetCount == 1)
    }
}
