// The Spellcasting section (issue #470, roadmap item 19.7): its accessibility
// ids, the seven controls' routing, and the readout with and without a runtime.
//
// The panel and the fake provider are `CombatPhysicsPanelTests`', for the reason
// `CombatMagicEffectsPanelTests` reuses them: what is under test is what the
// section sends and shows, not how the panel is built.

import AppKit
@testable import opensky
import Testing

@MainActor
struct CombatSpellcastingPanelTests {
    private func snapshot(
        spells: [KnownSpellReadout] = [],
        failures: [String] = [],
        unheldAbilityEntries: Int = 0
    ) -> CastingControlSnapshot {
        CastingControlSnapshot(
            isAvailable: true,
            knownSpells: spells,
            selectedSpellName: spells.first?.name,
            leftPhase: .idle,
            rightPhase: .charging,
            magicka: 60,
            maximumMagicka: 100,
            carriedTomeNames: ["Spell Tome: Healing"],
            readBookCount: 1,
            castCount: 2,
            concentrationSeconds: 4,
            failureCount: failures.count,
            failureLines: failures,
            unheldAbilityEntries: unheldAbilityEntries,
            lastActionText: "Readied Healing in the right hand."
        )
    }

    private var healingLine: KnownSpellReadout {
        KnownSpellReadout(
            name: "Healing",
            typeName: "spell",
            castingName: "concentration",
            deliveryName: "self",
            cost: 12,
            chargeTime: 0,
            readiedHands: ["right hand"]
        )
    }

    /// The ids are the UI-test API and are asserted as literals.
    @Test func theSectionCarriesItsAccessibilityIdentifiers() throws {
        let providers = FakeWorldProviders()
        let panel = try CombatPhysicsPanelTests.panel(providers: providers)
        panel.startInspecting()
        defer { panel.stopInspecting() }
        let section = panel.spellcastingSection

        #expect(section.sectionIdentifier == "combatSpellcasting")
        #expect(section.learnControl.accessibilityIdentifier() == "SpellcastingLearnControl")
        #expect(
            section.readTomeControl.accessibilityIdentifier() == "SpellcastingReadTomeControl"
        )
        #expect(section.selectControl.accessibilityIdentifier() == "SpellcastingSelectControl")
        #expect(
            section.readyRightControl.accessibilityIdentifier()
                == "SpellcastingReadyRightControl"
        )
        #expect(
            section.readyLeftControl.accessibilityIdentifier() == "SpellcastingReadyLeftControl"
        )
        #expect(
            section.castRightControl.accessibilityIdentifier() == "SpellcastingCastRightControl"
        )
        #expect(
            section.castLeftControl.accessibilityIdentifier() == "SpellcastingCastLeftControl"
        )
    }

    @Test func everyControlRoutesToTheProviderAndNamesItsHand() throws {
        let providers = FakeWorldProviders()
        providers.casting.snapshot = snapshot()
        let panel = try CombatPhysicsPanelTests.panel(providers: providers)
        panel.startInspecting()
        defer { panel.stopInspecting() }
        let section = panel.spellcastingSection

        for control in [
            section.learnControl, section.readTomeControl, section.selectControl,
            section.readyRightControl, section.readyLeftControl,
            section.castRightControl, section.castLeftControl
        ] {
            _ = control.target?.perform(control.action, with: control)
        }

        #expect(providers.casting.learnCount == 1)
        #expect(providers.casting.readTomeCount == 1)
        #expect(providers.casting.selectCount == 1)
        #expect(providers.casting.readied == [.right, .left])
        #expect(providers.casting.cast == [.right, .left])
    }

    @Test func theControlsAreDisabledWithoutAProvider() {
        let section = CombatSpellcastingSection()
        section.loadViewIfNeeded()
        section.syncControls()

        #expect(!section.learnControl.isEnabled)
        #expect(!section.castRightControl.isEnabled)
    }

    // MARK: - Readout

    @Test func theReadoutNamesEverySpellItsHandsAndItsCost() {
        let text = CastingControlReadout.text(for: snapshot(spells: [healingLine]))

        #expect(text.contains("Known spells (1):"))
        #expect(text.contains("Healing (spell, concentration, self) costs 12"))
        #expect(text.contains("readied in right hand"))
        #expect(text.contains("Hands: left idle, right charging"))
        #expect(text.contains("magicka 60 / 100"))
        #expect(text.contains("Tomes: Spell Tome: Healing — 1 book(s) already read"))
        #expect(text.contains("Casts: 2 completed, 4 second(s) maintained"))
    }

    /// The point of the tally: unimplemented ground is measured rather than
    /// silent.
    @Test func theReadoutSpellsOutEveryRefusalAndTheAbilityGap() {
        let text = CastingControlReadout.coverageText(
            for: snapshot(
                failures: ["aimed delivery is not implemented yet x 3"],
                unheldAbilityEntries: 2
            )
        )

        #expect(text.contains("1 refusal(s)"))
        #expect(text.contains("aimed delivery is not implemented yet x 3"))
        #expect(text.contains("2 ability entr(ies) carry no duration"))
    }

    @Test func aRuntimelessReadoutSaysSoRatherThanShowingAnEmptySpellbook() {
        let text = CastingControlReadout.text(for: .unavailable)

        #expect(text.contains("Known spells: unavailable"))
        #expect(text.contains("Hands: unavailable"))
        #expect(text.contains("Spellcasting unavailable: no game data loaded."))
    }

    @Test func anEmptySpellbookNamesTheControlThatFillsIt() {
        let text = CastingControlReadout.spellsText(for: snapshot())

        #expect(text.contains("Learn start spells"))
    }
}
