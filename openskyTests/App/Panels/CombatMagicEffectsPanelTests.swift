// The Magic Effects section (issue #469, roadmap item 19.6): its accessibility
// ids, the two controls' routing, and the readout with and without a runtime.
//
// The panel and the fake provider are `CombatPhysicsPanelTests`', for the reason
// `CombatActorValuesPanelTests` reuses them: what is under test is what the
// section sends and shows, not how the panel is built.

import AppKit
@testable import opensky
import Testing

@MainActor
struct CombatMagicEffectsPanelTests {
    private func snapshot(
        effects: [ActiveEffectReadout] = [],
        nearestActorName: String? = nil,
        nearestActorEffects: [ActiveEffectReadout] = [],
        skipped: Int = 0,
        unimplemented: [String] = []
    ) -> MagicEffectControlSnapshot {
        MagicEffectControlSnapshot(
            isAvailable: true,
            playerEffects: effects,
            nearestActorName: nearestActorName,
            nearestActorEffects: nearestActorEffects,
            runtimeActorCount: 1,
            appliedCount: 2,
            instantCount: 3,
            expiredCount: 1,
            dispelledCount: 0,
            skippedCount: skipped,
            unimplementedLines: unimplemented,
            lastActionText: "Drank TestHealingPotion."
        )
    }

    private var fortifyLine: ActiveEffectReadout {
        ActiveEffectReadout(
            name: "Fortify Resist Fire",
            sourceName: "potion",
            mode: .modifier,
            isDetrimental: false,
            magnitude: 20,
            duration: 60,
            remaining: 45,
            valueNames: ["Resist Fire"]
        )
    }

    /// The two ids are the UI-test API and are asserted as literals.
    @Test func theSectionCarriesItsAccessibilityIdentifiers() throws {
        let providers = FakeWorldProviders()
        let panel = try CombatPhysicsPanelTests.panel(providers: providers)
        panel.startInspecting()
        defer { panel.stopInspecting() }
        #expect(panel.magicEffectsSection.sectionIdentifier == "combatMagicEffects")
        #expect(
            panel.magicEffectsSection.consumeControl.accessibilityIdentifier()
                == "MagicEffectConsumeControl"
        )
        #expect(
            panel.magicEffectsSection.dispelControl.accessibilityIdentifier()
                == "MagicEffectDispelControl"
        )
    }

    /// Both buttons route to the provider rather than doing anything themselves.
    @Test func theControlsRouteToTheProvider() throws {
        let providers = FakeWorldProviders()
        let panel = try CombatPhysicsPanelTests.panel(providers: providers)
        sendScriptsControl(panel.magicEffectsSection.consumeControl)
        sendScriptsControl(panel.magicEffectsSection.dispelControl)
        #expect(providers.magicEffects.consumeCount == 1)
        #expect(providers.magicEffects.dispelCount == 1)
    }

    /// With no runtime the section says so rather than showing a convincing
    /// empty effect list.
    @Test func withNoRuntimeTheSectionSaysSo() throws {
        let providers = FakeWorldProviders()
        let panel = try CombatPhysicsPanelTests.panel(providers: providers)
        panel.startInspecting()
        defer { panel.stopInspecting() }
        let readout = try #require(
            scriptsReadout("CombatMagicEffectsStatsLabel", in: panel.view)
        )
        #expect(readout.contains("Player effects: unavailable"))
    }

    /// A running effect is listed with what it does and how long it has left.
    @Test func aRunningEffectIsListedWithItsRemainingDuration() {
        let text = MagicEffectControlReadout.text(for: snapshot(effects: [fortifyLine]))
        #expect(text.contains("Player effects (1)"))
        #expect(text.contains("Fortify Resist Fire (potion) restores Resist Fire"))
        #expect(text.contains("45.0s of 60.0s left"))
        #expect(text.contains("Applied: 2 timed, 3 instant"))
    }

    /// Nothing running is stated rather than left blank.
    @Test func noRunningEffectIsStated() {
        let text = MagicEffectControlReadout.text(for: snapshot())
        #expect(text.contains("Player effects: none running"))
        #expect(text.contains("Coverage: every effect entry applied"))
    }

    /// The nearest resident actor's list (issue #475, roadmap item 19.12): the
    /// actor the resistance values above are read about, so a hostile spell
    /// that landed on an NPC is visible beside what scaled it.
    @Test func theNearestActorsEffectsAreListedUnderTheirOwnName() {
        let text = MagicEffectControlReadout.text(
            for: snapshot(
                nearestActorName: "0x0001A69A (base 0x00013481)",
                nearestActorEffects: [fortifyLine]
            )
        )
        #expect(text.contains("Nearest actor effects — 0x0001A69A (base 0x00013481) (1):"))
        #expect(text.contains("Fortify Resist Fire (potion) restores Resist Fire"))
    }

    /// No actor resident and an actor with nothing running are different
    /// states, and the readout spells them differently.
    @Test func anAbsentActorAndAQuietActorReadDifferently() {
        #expect(
            MagicEffectControlReadout.nearestActorEffectsText(for: snapshot())
                == "Nearest actor effects: none resident"
        )
        #expect(
            MagicEffectControlReadout
                .nearestActorEffectsText(for: snapshot(nearestActorName: "Bandit"))
                == "Nearest actor effects: none running on Bandit"
        )
        #expect(
            MagicEffectControlReadout.nearestActorEffectsText(for: .unavailable)
                == "Nearest actor effects: unavailable"
        )
    }

    /// Unimplemented ground is measured on the readout, which is the whole
    /// point of the tally.
    @Test func unimplementedArchetypesAreNamedOnTheReadout() {
        let text = MagicEffectControlReadout.text(
            for: snapshot(skipped: 4, unimplemented: ["paralysis x3", "calm x1"])
        )
        #expect(text.contains("Coverage: 4 entr(ies) skipped"))
        #expect(text.contains("paralysis x3, calm x1"))
    }
}
