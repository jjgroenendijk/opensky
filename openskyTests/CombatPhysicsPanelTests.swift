// World > Combat & Physics verification-surface coverage (issue #198, roadmap
// item 15.9): the panel the registry factory builds, the literal
// accessibility-id contract for the three sections this item added, the
// readouts they render from one snapshot, and the provider round trip for every
// control.
//
// The Melee, Archery and Death & Ragdoll sections that moved here from
// `World > Player & Locomotion` keep their own suites — `CombatMeleePanelTests`,
// `CombatArcheryPanelTests`, `CombatRagdollPanelTests` — so this file covers
// what item 15.9 added rather than re-covering all six.

import AppKit
@testable import opensky
import Testing

struct CombatPhysicsPanelTests {
    @Test @MainActor
    func registryFactoryBuildsThePanelWithEveryProviderWired() throws {
        let providers = FakeWorldProviders()
        let panel = try Self.panel(providers: providers)
        #expect(panel.actorValueProvider === providers)
        #expect(panel.meleeProvider === providers)
        #expect(panel.archeryProvider === providers)
        #expect(panel.ragdollProvider === providers)
        #expect(panel.combatProvider === providers)
        #expect(panel.physicsProvider === providers)
        #expect(panel.magicEffectProvider === providers)
        #expect(panel.castingProvider === providers)
        #expect(panel.makeSections().count == 8)
    }

    /// Accessibility ids are the UI-test API (docs/tools/app-ui.md); pin the
    /// set this item added literally, and check every control is laid out and
    /// visible rather than merely constructed.
    @Test @MainActor
    func accessibilityIdentifiersArePinnedAndControlsAreVisible() throws {
        let panel = CombatPhysicsPanelViewController()
        let scrollView = try #require(panel.view as? NSScrollView)
        panel.view.frame = NSRect(x: 0, y: 0, width: 300, height: 2400)
        panel.view.layoutSubtreeIfNeeded()

        #expect(panel.actorValuesSection.sectionIdentifier == "combatActorValues")
        #expect(panel.loopSection.sectionIdentifier == "combatLoop")
        #expect(panel.physicsSection.sectionIdentifier == "combatPhysics")

        let ids: [(NSView, String)] = [
            (panel.actorValuesSection.targetControl, "ActorValueTargetControl"),
            (panel.actorValuesSection.kindControl, "ActorValueKindControl"),
            (panel.actorValuesSection.valueNameControl, "ActorValueNameControl"),
            (panel.actorValuesSection.amountControl, "ActorValueAmountControl"),
            (panel.damageControl, "ActorValueDamageControl"),
            (panel.actorValuesSection.setControl, "ActorValueSetControl"),
            (panel.actorValuesSection.restoreControl, "ActorValueRestoreControl"),
            (panel.actorValuesSection.refillControl, "ActorValueRefillControl"),
            (panel.actorValuesSection.resetControl, "ActorValueResetControl"),
            (panel.hostilityControl, "CombatHostilityControl"),
            (panel.clearCombatTraceControl, "CombatClearTraceControl"),
            (panel.physicsFreezeControl, "PhysicsFreezeControl"),
            (panel.physicsResetControl, "PhysicsResetControl")
        ]
        for (control, identifier) in ids {
            #expect(control.accessibilityIdentifier() == identifier)
            #expect(!control.isHidden)
            #expect(control.frame.height > 0)
            #expect(control.isDescendant(of: scrollView))
        }
        for identifier in [
            "CombatActorValuesStatsLabel", "CombatMeleeStatsLabel",
            "CombatArcheryStatsLabel", "CombatRagdollStatsLabel",
            "CombatLoopStatsLabel", "CombatPhysicsStatsLabel"
        ] {
            #expect(scriptsReadout(identifier, in: panel.view) != nil, "\(identifier) is missing")
        }
    }

    // MARK: - Actor values

    @Test @MainActor
    func theActorValueReadoutNamesBothActorsAndTheirDerivation() throws {
        let providers = FakeWorldProviders()
        providers.actorValues.snapshot = Self.actorValueSnapshot()
        let panel = try Self.panel(providers: providers)
        panel.startInspecting()
        defer { panel.stopInspecting() }

        let readout = try #require(
            scriptsReadout("CombatActorValuesStatsLabel", in: panel.view)
        )
        #expect(readout.contains("Player: Player — HP 80/100"))
        #expect(readout.contains("Nearest actor: Bandit — HP 0/120"))
        #expect(readout.contains("(down)"))
        #expect(readout.contains("Derivation: level 6, auto-calculated per level"))
        #expect(readout.contains("Controls: acting on the nearest actor"))
        #expect(readout.contains("Damaged Bandit."))
        // Item 19.5 (issue #468): the selected value, its modifier slots and
        // the capped resistance fraction it reads as.
        #expect(readout.contains("Selected value: Resist Fire (41) — 25.0  base 40.0"))
        #expect(readout.contains("dmg -15.0"))
        #expect(readout.contains("resists 25% (capped)"))
    }

    /// A field holding something that is not a number falls back to the
    /// documented default instead of sending a NaN into the runtime.
    @Test @MainActor
    func anUnparsableAmountFallsBackToTheDefault() throws {
        let providers = FakeWorldProviders()
        let panel = try Self.panel(providers: providers)
        panel.actorValuesSection.amountControl.stringValue = "lots"
        sendScriptsControl(panel.damageControl)
        #expect(
            providers.actorValues.damages.last?.amount
                == CombatActorValuesSection.defaultAmount
        )
    }

    // MARK: - Combat loop

    @Test @MainActor
    func theCombatReadoutDescribesTheFightAndItsTransients() throws {
        let providers = FakeWorldProviders()
        providers.combatLoop.snapshot = Self.combatSnapshot()
        let panel = try Self.panel(providers: providers)
        panel.startInspecting()
        defer { panel.stopInspecting() }

        let readout = try #require(scriptsReadout("CombatLoopStatsLabel", in: panel.view))
        #expect(readout.contains("Combat: in combat with Bandit"))
        #expect(readout.contains("Fighters: 1"))
        #expect(readout.contains("Bandit: windup, detected"))
        #expect(readout.contains("2 contact frames"))
        #expect(readout.contains("Hostility: Bandit is hostile"))
        #expect(readout.contains("Hits taken: 2"))
        #expect(readout.contains("arrows in flight 1/"))
    }

    @Test @MainActor
    func everyCombatControlReachesTheProvider() throws {
        let providers = FakeWorldProviders()
        let panel = try Self.panel(providers: providers)

        panel.hostilityControl.state = .on
        sendScriptsControl(panel.hostilityControl)
        #expect(providers.selectedActorIsHostile)
        panel.hostilityControl.state = .off
        sendScriptsControl(panel.hostilityControl)
        #expect(!providers.selectedActorIsHostile)

        sendScriptsControl(panel.clearCombatTraceControl)
        #expect(providers.combatLoop.traceClearCount == 1)
    }

    // MARK: - Physics

    @Test @MainActor
    func thePhysicsReadoutCountsTheBodiesAndTheLastStep() throws {
        let providers = FakeWorldProviders()
        providers.physics.snapshot = DynamicBodyStatsSnapshot(
            bodyCount: 12, activeBodyCount: 3, sleepingBodyCount: 9,
            contactCount: 7, substepCount: 2, recoveredBodyCount: 0, isFrozen: false
        )
        let panel = try Self.panel(providers: providers)
        panel.startInspecting()
        defer { panel.stopInspecting() }

        let readout = try #require(scriptsReadout("CombatPhysicsStatsLabel", in: panel.view))
        #expect(readout.contains("Bodies: 12 (3 awake, 9 asleep)"))
        #expect(readout.contains("Last step: 7 contacts over 2 substeps"))
        #expect(readout.contains("Stability: no pose recovery needed"))
    }

    /// The freeze is the destination's one override, and the sidebar's own
    /// reset releases it without touching anything the fight did.
    @Test @MainActor
    func freezingIsTheOnlyOverrideAndTheSidebarResetReleasesIt() throws {
        let providers = FakeWorldProviders()
        let panel = try Self.panel(providers: providers)
        let descriptor = try #require(DestinationRegistry.destination(id: "combatPhysics"))
        let overrides = try #require(descriptor.overrides)
        let context = WorldPanelContext(providers: providers)

        sendScriptsControl(panel.clearCombatTraceControl)
        sendScriptsControl(panel.physicsResetControl)
        #expect(!overrides.isOverridden(context), "an action must not light the dot")
        #expect(providers.physics.resetCount == 1)

        panel.physicsFreezeControl.state = .on
        sendScriptsControl(panel.physicsFreezeControl)
        #expect(providers.dynamicBodyStatsSnapshot.isFrozen)
        #expect(overrides.isOverridden(context))

        overrides.resetToDefaults(context)
        #expect(!overrides.isOverridden(context))
        // The trace the user cleared stayed cleared across the reset, which is
        // the whole point of keeping world actions out of the override.
        #expect(providers.combatLoop.traceClearCount == 1)
    }

    // MARK: - Fixtures

    private static func actorValueSnapshot() -> ActorValueControlSnapshot {
        ActorValueControlSnapshot(
            isAvailable: true,
            player: ActorValueReadout(
                name: "Player",
                current: ActorValues(health: 80, magicka: 100, stamina: 90),
                maximums: ActorValues(health: 100, magicka: 100, stamina: 100),
                regenPercentPerSecond: ActorValues(health: 0.7, magicka: 3, stamina: 5),
                level: 1,
                autoCalculatesStats: false,
                hasZeroHealth: false
            ),
            nearestActor: ActorValueReadout(
                name: "Bandit",
                current: ActorValues(health: 0, magicka: 50, stamina: 60),
                maximums: ActorValues(health: 120, magicka: 50, stamina: 80),
                regenPercentPerSecond: ActorValues(health: 0.7, magicka: 3, stamina: 5),
                level: 6,
                autoCalculatesStats: true,
                hasZeroHealth: true
            ),
            target: .nearestActor,
            // A resistance rather than a primary, so the panel test covers the
            // line item 19.5 added (issue #468).
            selection: ActorValueInspection(
                name: "Resist Fire",
                index: 41,
                current: 25,
                base: 40,
                permanent: 0,
                temporary: 0,
                damage: -15,
                resistanceFraction: 0.25
            ),
            runtimeActorCount: 3,
            lastActionText: "Damaged Bandit."
        )
    }

    private static func combatSnapshot() -> CombatLoopSnapshot {
        CombatLoopSnapshot(
            isAvailable: true,
            isPlayerInCombat: true,
            targetName: "Bandit",
            targetDistance: 96,
            hostileCount: 1,
            deadCount: 0,
            engagedCount: 1,
            searchingCount: 0,
            actors: [CombatActorReadout(
                key: .generated(1),
                name: "Bandit",
                phase: .windup,
                awareness: .detected,
                distance: 96,
                healthFraction: 0.5,
                attackCount: 3,
                contactCount: 2,
                blockCount: 1,
                searchCount: 0
            )],
            crowdedOutCount: 0,
            selectedActorName: "Bandit",
            selectedActorIsHostile: true,
            incomingHitCount: 2,
            incomingTrace: ["attack 2 from Bandit: 6.0 damage"],
            damageFlash: 0.5,
            transients: CombatTransientCounts(
                liveProjectiles: 1, stuckProjectiles: 2, activeRagdolls: 0, awakeBodies: 4
            ),
            limits: .standard,
            trimmedTransients: .none,
            lastActionText: "Bandit is now hostile."
        )
    }

    /// Not private: `CombatActorValuesPanelTests` builds the same panel.
    @MainActor
    static func panel(
        providers: FakeWorldProviders
    ) throws -> CombatPhysicsPanelViewController {
        let descriptor = try #require(DestinationRegistry.destination(id: "combatPhysics"))
        guard case let .worldInspector(makePanel) = descriptor.content else {
            Issue.record("combatPhysics is not a world inspector")
            throw CombatPhysicsPanelTestError.notAWorldInspector
        }
        let panel = try #require(
            makePanel(WorldPanelContext(providers: providers))
                as? CombatPhysicsPanelViewController
        )
        panel.loadViewIfNeeded()
        return panel
    }
}

private enum CombatPhysicsPanelTestError: Error {
    case notAWorldInspector
}
