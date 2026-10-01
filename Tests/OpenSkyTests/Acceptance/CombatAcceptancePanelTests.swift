// M15 panel acceptance: one run through the real sidebar model and the
// registry-built World > Combat & Physics panel on one provider set, found by
// accessibility id. It checks the destination as one surface, in session order:
// look, draw, swing, shoot, kill, calm down, freeze physics.

import AppKit
@testable import OpenSky
@testable import OpenSkyActorsInterface
@testable import OpenSkyCombat
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyPerceptionInterface
@testable import OpenSkyPhysics
import simd
import TagsTesting
import Testing

@Suite(.tags(.acceptance))
@MainActor
struct CombatAcceptancePanelTests {
    @Test
    func theCombatDestinationRunsTheWholeAcceptanceFlow() throws {
        let providers = FakeWorldProviders()
        providers.actorValues.snapshot = Self.actorValues
        providers.melee.snapshot = Self.melee
        providers.archery.snapshot = Self.archery
        providers.ragdoll.snapshot = Self.ragdoll
        providers.combatLoop.snapshot = Self.combat
        providers.physics.snapshot = Self.physics

        let panel = try Self.buildPanel(providers: providers)
        panel.startInspecting()
        defer { panel.stopInspecting() }

        Self.expectEveryReadout(panel)
        Self.damageAnActor(panel, providers: providers)
        Self.fightWithBothWeapons(panel, providers: providers)
        Self.killAndCollapse(panel, providers: providers)
        try Self.freezeThePhysicsAndReleaseIt(panel, providers: providers)
    }

    // MARK: - The run

    /// The sidebar row and the registry factory, taken through the same path
    /// the app takes rather than by constructing the panel directly.
    private static func buildPanel(
        providers: FakeWorldProviders
    ) throws -> CombatPhysicsPanelViewController {
        try buildWorldPanel("combatPhysics", title: "Combat & Physics", providers: providers)
    }

    /// Every readout the destination publishes, read back by accessibility id.
    /// A session mid-fight has to be legible in all six.
    private static func expectEveryReadout(_ panel: CombatPhysicsPanelViewController) {
        let view = panel.view
        #expect(scriptsReadout("CombatActorValuesStatsLabel", in: view)?
            .contains("Nearest actor: Bandit — HP 30/120") == true)
        #expect(scriptsReadout("CombatMeleeStatsLabel", in: view)?
            .contains("IronSword") == true)
        #expect(scriptsReadout("CombatArcheryStatsLabel", in: view)?
            .contains("LongBow") == true)
        #expect(scriptsReadout("CombatRagdollStatsLabel", in: view)?
            .contains("Bone bodies: 18 over 17 joints") == true)
        #expect(scriptsReadout("CombatLoopStatsLabel", in: view)?
            .contains("Combat: in combat with Bandit") == true)
        #expect(scriptsReadout("CombatPhysicsStatsLabel", in: view)?
            .contains("Bodies: 9 (2 awake, 7 asleep)") == true)
    }

    /// Step 1 — the actor-value controls, which are what make a fight visible
    /// as numbers before a single blow is struck.
    private static func damageAnActor(
        _ panel: CombatPhysicsPanelViewController,
        providers: FakeWorldProviders
    ) {
        let section = panel.actorValuesSection
        section.targetControl.selectItem(at: 1)
        sendScriptsControl(section.targetControl)
        #expect(providers.actorValueTarget == .nearestActor)

        section.amountControl.stringValue = "30"
        sendScriptsControl(panel.damageControl)
        #expect(providers.actorValues.damages.last?.kind == .health)
        #expect(providers.actorValues.damages.last?.amount == 30)
    }

    /// Step 2 — both weapon classes, driven from the panel: the draw checkbox,
    /// the attack button, and the archery spawn.
    private static func fightWithBothWeapons(
        _ panel: CombatPhysicsPanelViewController,
        providers: FakeWorldProviders
    ) {
        panel.weaponDrawnControl.state = .on
        sendScriptsControl(panel.weaponDrawnControl)
        #expect(providers.melee.isWeaponDrawn)

        sendScriptsControl(panel.attackControl)
        #expect(providers.melee.attackRequests == 1)

        sendScriptsControl(panel.archerySpawnControl)
        #expect(providers.archery.spawnRequests == 1)
    }

    /// Step 3 — the hostility toggle, the dev target, and the ragdoll trigger:
    /// the whole "make it fight back and then put it down" loop, from controls.
    private static func killAndCollapse(
        _ panel: CombatPhysicsPanelViewController,
        providers: FakeWorldProviders
    ) {
        panel.hostilityControl.state = .on
        sendScriptsControl(panel.hostilityControl)
        #expect(providers.selectedActorIsHostile)

        sendScriptsControl(panel.ragdollTriggerControl)
        #expect(providers.ragdoll.triggerRequests == 1)

        sendScriptsControl(panel.clearCombatTraceControl)
        #expect(providers.combatLoop.traceClearCount == 1)
    }

    /// Step 4 — the destination's override policy: a fight is not an override,
    /// a frozen simulation is, and the sidebar's own reset releases the freeze
    /// without undoing a single thing the fight did.
    private static func freezeThePhysicsAndReleaseIt(
        _ panel: CombatPhysicsPanelViewController,
        providers: FakeWorldProviders
    ) throws {
        let descriptor = try #require(DestinationRegistry.destination(id: "combatPhysics"))
        let context = WorldPanelContext(providers: providers)
        let overrides = try #require(descriptor.overrides)
        #expect(!overrides.isOverridden(context), "fighting must not light the dot")

        panel.physicsFreezeControl.state = .on
        sendScriptsControl(panel.physicsFreezeControl)
        #expect(providers.dynamicBodyStatsSnapshot.isFrozen)
        #expect(overrides.isOverridden(context))
        panel.startInspecting()
        #expect(scriptsReadout("CombatPhysicsStatsLabel", in: panel.view)?
            .contains("frozen") == true)

        sendScriptsControl(panel.physicsResetControl)
        #expect(providers.physics.resetCount == 1)

        // The sidebar's own reset, not the panel's checkbox: it is the registry
        // contract that has to release the freeze.
        overrides.resetToDefaults(context)
        #expect(!overrides.isOverridden(context))
        // Everything the fight did survived it, which is the whole point of
        // keeping world actions out of the override.
        #expect(providers.melee.attackRequests == 1)
        #expect(providers.ragdoll.triggerRequests == 1)
        #expect(providers.actorValues.damages.count == 1)
    }

    // MARK: - Fixtures

    /// The session the readouts describe: a wounded opponent, a drawn sword, a
    /// bow at full draw, a corpse mid-collapse, a live fight and settled
    /// clutter.
    private static let actorValues = ActorValueControlSnapshot(
        isAvailable: true,
        player: ActorValueReadout(
            name: "Player",
            current: ActorValues(health: 92, magicka: 100, stamina: 100),
            maximums: ActorValues(health: 100, magicka: 100, stamina: 100),
            regenPercentPerSecond: ActorValues(health: 0.7, magicka: 3, stamina: 5),
            level: 1,
            autoCalculatesStats: false,
            hasZeroHealth: false
        ),
        nearestActor: ActorValueReadout(
            name: "Bandit",
            current: ActorValues(health: 30, magicka: 50, stamina: 80),
            maximums: ActorValues(health: 120, magicka: 50, stamina: 80),
            regenPercentPerSecond: ActorValues(health: 0.7, magicka: 3, stamina: 5),
            level: 6,
            autoCalculatesStats: true,
            hasZeroHealth: false
        ),
        target: .player,
        selection: ActorValueInspection(
            name: "Health",
            index: 24,
            current: 92,
            base: 100,
            permanent: 0,
            temporary: 0,
            damage: 0,
            resistanceFraction: nil
        ),
        runtimeActorCount: 4,
        lastActionText: "Damaged Bandit: 30.0 / 50.0 / 80.0."
    )

    private static let melee = MeleeCombatSnapshot(
        isAvailable: true,
        drawState: .drawn,
        attackPhase: .contact,
        isBlocking: false,
        isStaggering: false,
        weaponName: "IronSword",
        weaponDamage: 7,
        weaponReachMultiplier: 0.7,
        weaponSpeed: 1,
        rightHandType: .sword,
        leftHandType: .shield,
        reach: 98.7,
        swingCount: 3,
        hitCount: 2,
        trace: [],
        settings: ["fCombatDistance = 141.000 [Skyrim.esm]"]
    )

    private static let archery = ArcherySnapshot(
        isAvailable: true,
        phase: .drawn,
        hasArrowAttached: true,
        heldSeconds: 1.1,
        lastHeldSeconds: 1,
        drawFraction: 1,
        bowName: "LongBow",
        bowDamage: 6,
        bowSpeed: 1,
        arrowName: "IronArrow",
        arrowDamage: 8,
        projectileName: "ArrowIronProjectile",
        projectileSpeed: 3600,
        projectileGravityFactor: 0.35,
        projectileRange: 60000,
        drawRequestCount: 2,
        firedCount: 1,
        impactCount: 1,
        liveCount: 1,
        stuckCount: 2,
        trace: [],
        settings: []
    )

    private static let ragdoll = RagdollStatsSnapshot(
        ragdollCount: 1,
        activeRagdollCount: 1,
        settledRagdollCount: 0,
        boneBodyCount: 18,
        jointCount: 17,
        jointViolationCount: 0,
        recoveredBodyCount: 0,
        isFrozen: false
    )

    private static let combat = CombatLoopSnapshot(
        isAvailable: true,
        isPlayerInCombat: true,
        targetName: "Bandit",
        targetDistance: 120,
        hostileCount: 1,
        deadCount: 0,
        engagedCount: 1,
        searchingCount: 0,
        actors: [CombatActorReadout(
            key: .generated(1),
            name: "Bandit",
            phase: .windup,
            awareness: .detected,
            distance: 120,
            healthFraction: 0.75,
            attackCount: 2,
            contactCount: 1,
            blockCount: 0,
            searchCount: 0
        )],
        crowdedOutCount: 0,
        selectedActorName: "Bandit",
        selectedActorIsHostile: true,
        incomingHitCount: 1,
        incomingTrace: ["attack 1 from Bandit: 8.0 damage"],
        damageFlash: 0.4,
        transients: CombatTransientCounts(
            liveProjectiles: 1, stuckProjectiles: 2, activeRagdolls: 1, awakeBodies: 2
        ),
        limits: .standard,
        trimmedTransients: .none,
        isActorCastingEnabled: true,
        actorCastCount: 0,
        lastActionText: "Hostility: Bandit is now hostile."
    )

    private static let physics = DynamicBodyStatsSnapshot(
        bodyCount: 9,
        activeBodyCount: 2,
        sleepingBodyCount: 7,
        contactCount: 5,
        substepCount: 2,
        recoveredBodyCount: 0,
        isFrozen: false
    )
}

// Thrown only to end the run early when the registry hands back something
// other than a world inspector, which `Issue.record` has already reported.
