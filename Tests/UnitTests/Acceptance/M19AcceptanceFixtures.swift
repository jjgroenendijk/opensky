// The session `M19AcceptancePanelTests` reads: a player mid-fight who has
// learned Firebolt and readied it right-handed, a bandit that has just taken it
// through a 40% fire resistance, and the fighter's own casting switched on.
//
// Split out of the suite for the reason `M10AcceptanceFixture` was: one
// milestone's worth of snapshot literals is past the strict-lint type-length
// cap, and what is under test is the surface rather than the numbers.

@testable import opensky

@MainActor
enum M19Fixture {
    static let actorValues = ActorValueControlSnapshot(
        isAvailable: true,
        player: ActorValueReadout(
            name: "Player",
            current: ActorValues(health: 500, magicka: 59, stamina: 100),
            maximums: ActorValues(health: 500, magicka: 100, stamina: 100),
            regenPercentPerSecond: ActorValues(health: 0.7, magicka: 3, stamina: 5),
            level: 1,
            autoCalculatesStats: false,
            hasZeroHealth: false
        ),
        nearestActor: ActorValueReadout(
            name: "Bandit",
            current: ActorValues(health: 485, magicka: 50, stamina: 100),
            maximums: ActorValues(health: 500, magicka: 50, stamina: 100),
            regenPercentPerSecond: ActorValues(health: 0.7, magicka: 3, stamina: 5),
            level: 6,
            autoCalculatesStats: true,
            hasZeroHealth: false
        ),
        target: .nearestActor,
        selection: ActorValueInspection(
            name: "Resist Fire",
            index: 41,
            current: 40,
            base: 40,
            permanent: 0,
            temporary: 0,
            damage: 0,
            resistanceFraction: 0.4
        ),
        runtimeActorCount: 2,
        lastActionText: "Selected Resist Fire (41)."
    )

    static let magicEffects = MagicEffectControlSnapshot(
        isAvailable: true,
        playerEffects: [ActiveEffectReadout(
            name: "Fortify Resist Fire",
            sourceName: "potion",
            mode: .modifier,
            isDetrimental: false,
            magnitude: 20,
            duration: 60,
            remaining: 45,
            valueNames: ["Resist Fire"]
        )],
        nearestActorName: "Bandit",
        nearestActorEffects: [ActiveEffectReadout(
            name: "Firebolt",
            sourceName: "spell",
            mode: .perSecond,
            isDetrimental: true,
            magnitude: 15,
            duration: 0,
            remaining: 0,
            valueNames: ["Health"]
        )],
        runtimeActorCount: 2,
        appliedCount: 2,
        instantCount: 1,
        expiredCount: 0,
        dispelledCount: 0,
        skippedCount: 0,
        unimplementedLines: [],
        lastActionText: "Cast Firebolt with the right hand."
    )

    static let casting = CastingControlSnapshot(
        isAvailable: true,
        knownSpells: [
            KnownSpellReadout(
                name: "Firebolt",
                typeName: "spell",
                castingName: "fire and forget",
                deliveryName: "aimed",
                cost: 41,
                chargeTime: 0.5,
                readiedHands: ["right hand"]
            ),
            KnownSpellReadout(
                name: "Healing",
                typeName: "spell",
                castingName: "concentration",
                deliveryName: "self",
                cost: 12,
                chargeTime: 0,
                readiedHands: []
            )
        ],
        selectedSpellName: "Firebolt",
        leftPhase: .idle,
        rightPhase: .idle,
        magicka: 59,
        maximumMagicka: 100,
        carriedTomeNames: ["Spell Tome: Firebolt"],
        readBookCount: 1,
        castCount: 1,
        concentrationSeconds: 0,
        failureCount: 0,
        failureLines: [],
        unheldAbilityEntries: 0,
        projectileCount: 1,
        deliveryLines: ["aimed x 1"],
        lastHitTargets: 1,
        lastHitAdjustments: ["FireDamageFFAimed on Bandit: 25.0 x 0.600 = 15.0"],
        conditionLines: ["HasSpell(Firebolt) -> 1", "GetCurrentDeliveryType(right hand) -> 2"],
        lastActionText: "Cast Firebolt with the right hand."
    )

    static let combatLoop = CombatLoopSnapshot(
        isAvailable: true,
        isPlayerInCombat: true,
        targetName: "Bandit",
        targetDistance: 583,
        hostileCount: 1,
        deadCount: 0,
        engagedCount: 1,
        searchingCount: 0,
        actors: [CombatActorReadout(
            key: .generated(1),
            name: "Bandit",
            phase: .windup,
            awareness: .detected,
            distance: 583,
            healthFraction: 0.97,
            attackCount: 1,
            contactCount: 0,
            blockCount: 0,
            searchCount: 0,
            castCount: 2,
            spellOptionCount: 1
        )],
        crowdedOutCount: 0,
        selectedActorName: "Bandit",
        selectedActorIsHostile: true,
        incomingHitCount: 1,
        incomingTrace: ["attack 1 from Bandit: 15.0 damage"],
        damageFlash: 0.3,
        transients: CombatTransientCounts(
            liveProjectiles: 1, stuckProjectiles: 0, activeRagdolls: 0, awakeBodies: 1
        ),
        limits: .standard,
        trimmedTransients: .none,
        isActorCastingEnabled: true,
        actorCastCount: 2,
        lastActionText: "Hostility: Bandit is now hostile."
    )
}
