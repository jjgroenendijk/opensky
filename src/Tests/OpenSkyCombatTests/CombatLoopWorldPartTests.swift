// The combat loop's world over a fake `CombatWorld`: each answer reads the world, a
// combat part, or the shared state, and each request reaches the world or the queue.

@testable import OpenSkyActorsInterface
import OpenSkyBehavior
@testable import OpenSkyCombat
@testable import OpenSkyCombatInterface
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyMagicInterface
@testable import OpenSkyPhysics
import OpenSkyProgressionInterface
@testable import OpenSkyWorldState
import simd
import Testing

@MainActor
struct CombatLoopWorldPartTests {
    private static let foe = ReferenceKey.generated(7)
    private static let ally = ReferenceKey.generated(8)

    private static func coordinator(_ world: FakeCoordinatorWorld) -> CombatCoordinator {
        CombatCoordinator(
            world: world, data: CombatSessionData(combat: .synthetic, archery: .synthetic)
        )
    }

    @Test func theLoopSeesTheResidentActorsAndThePlayer() {
        let world = FakeCoordinatorWorld()
        world.actors = [CombatActorObservation(key: Self.foe, feet: SIMD3(5, 0, 0))]
        let part = Self.coordinator(world).loopWorld
        #expect(part.combatActors().map(\.key) == [Self.foe])
        #expect(part.combatPlayer.key == .player)
        #expect(part.combatWeapon(of: Self.foe) == .unarmed)
        #expect(!part.combatInInterior)
        #expect(!part.combatFlies(Self.foe))
    }

    @Test func aLoopBlowWithoutAnAttackerLandsOnTheWorld() {
        let world = FakeCoordinatorWorld()
        let part = Self.coordinator(world).loopWorld
        #expect(part.applyCombatDamage(12, to: Self.foe))
        #expect(world.damage.map(\.amount) == [12])
        #expect(world.damage.map(\.key) == [Self.foe])
    }

    @Test func theTemperamentNeedsTheSwitchAndAConfidenceValue() {
        let world = FakeCoordinatorWorld()
        let coordinator = Self.coordinator(world)
        let part = coordinator.loopWorld
        #expect(part.combatTemperament(of: Self.foe, toward: .player) == nil)
        world.values[Self.foe] = [CombatLoopWorldPart.confidenceIndex: 2]
        #expect(part.combatTemperament(of: Self.foe, toward: .player)?.confidence == 2)
        coordinator.shared.usesTemperament = false
        #expect(part.combatTemperament(of: Self.foe, toward: .player) == nil)
    }

    @Test func anActorWithoutAReactionNeverAssists() {
        let world = FakeCoordinatorWorld()
        world.values[Self.ally] = [CombatLoopWorldPart.assistanceIndex: 2]
        #expect(!Self.coordinator(world).loopWorld.combatAssists(Self.ally, ally: Self.foe))
    }

    @Test func anActorWithoutAReactionCountsAsNoFriendOfThePlayer() {
        let part = Self.coordinator(FakeCoordinatorWorld()).loopWorld
        #expect(part.combatReaction(toPlayerOf: Self.ally) == nil)
    }

    @Test func theBlockAndItsTermsComeFromTheSharedParts() {
        let world = FakeCoordinatorWorld()
        world.perkMultipliers[Self.foe] = 0.5
        let part = Self.coordinator(world).loopWorld
        #expect(part.combatBlock(of: Self.foe) == nil)
        #expect(!part.combatWearsShield(Self.foe))
        #expect(part.combatBlockMultiplier(of: Self.foe) == 1)
        world.values[Self.foe] = [:]
        #expect(part.combatBlockMultiplier(of: Self.foe) == 0.5)
        #expect(part.combatBlockSkill(of: Self.foe) == MeleeDamage.defaultBlockSkill)
        let result = MeleeDamageResult(base: 10, blockedFraction: 0.5, applied: 5)
        part.applyCombatBlockStamina(result, to: Self.foe)
        #expect(world.staminaDamage.map(\.key) == [Self.foe])
    }

    @Test func anNPCBlowIsAPlainStrikeWithoutPerkSpells() {
        let world = FakeCoordinatorWorld()
        let part = Self.coordinator(world).loopWorld
        let blow = CombatBlow(attacker: Self.foe, handType: .handToHand, baseDamage: 4)
        #expect(part.combatStrike(blow, on: .player).sneakMultiplier == 1)
        part.applyCombatHitSpell(blow, on: .player)
        part.applyCombatSwingSpell(blow, at: .player)
        #expect(world.spellHits.isEmpty)
    }

    @Test func theAwarenessIsWhatTheWorldDetects() {
        let world = FakeCoordinatorWorld()
        world.detects[Self.foe] = [.player]
        let part = Self.coordinator(world).loopWorld
        #expect(part.combatAwareness(of: Self.foe, toward: .player).isDetected)
        #expect(!part.combatAwareness(of: Self.ally, toward: .player).isDetected)
    }

    @Test func castsAndMovesReachTheWorld() {
        let world = FakeCoordinatorWorld()
        let part = Self.coordinator(world).loopWorld
        let heal = CombatSpellOption(
            spell: .generated(201), cost: 30, range: 0, chargeSeconds: 0.2, purpose: .heal
        )
        #expect(part.beginCombatCast(heal, by: Self.foe))
        part.cancelCombatCast(by: Self.foe)
        #expect(world.cancelledCasts == [Self.foe])
        #expect(part.moveCombatActor(Self.foe, to: SIMD3(1, 0, 0)))
        #expect(part.moveCombatActor(Self.foe, to: SIMD3(2, 0, 0), gait: nil))
        part.turnCombatActor(Self.foe, toward: .zero)
        part.stopCombatMovement(of: Self.foe)
        part.resumeCombatPackage(for: Self.foe)
        #expect(!part.playCombatClip(.stagger, on: Self.foe))
    }

    @Test func clearingTransientsAndMusicQueueCommands() {
        let coordinator = Self.coordinator(FakeCoordinatorWorld())
        coordinator.loopWorld.despawnCombatTransients()
        coordinator.loopWorld.setCombatMusicActive(true)
        #expect(coordinator.takeCommands() == [.resetRagdolls, .setCombatMusic(active: true)])
    }

    @Test func theInfluenceOfAnActorIsNoneWithoutEffects() {
        let part = Self.coordinator(FakeCoordinatorWorld()).loopWorld
        #expect(!part.combatInfluence(of: Self.foe).isEthereal)
    }
}

/// The calls every combat world shares: the reporter, the graphs, and the queue.
@MainActor
struct CombatSharedPartTests {
    private static let foe = ReferenceKey.generated(7)

    @Test func reportsAndHitsReachTheWorldReporter() {
        let world = FakeCoordinatorWorld()
        let part = CombatCoordinator(world: world, data: nil).meleeWorld
        let use = SkillUseEvent(actor: .player, action: .sneakAttack, amount: 3)
        #expect(part.reportSkillUse(use) == 3)
        #expect(world.skillUses == [use])
        _ = part.reportScriptHit(ScriptHitEvent(target: Self.foe, aggressor: .player, damage: 3))
        let payload = SpellPayload(
            spell: .plugin(name: "base.esm", objectID: 0x600), sourcePlugin: "base.esm",
            caster: .player,
            entries: [], isHostile: true, ignoresResistance: false, projectile: nil, name: "Flames"
        )
        part.applySpellHit(SpellHit(payload: payload, targets: [SpellHitTarget(key: Self.foe)]))
        #expect(world.spellHits.count == 1)
        part.spellLanded(payload, at: .zero)
        part.applyWeaponPoison(WeaponPoisonHit(attacker: .player, weapon: nil, target: Self.foe))
        #expect(part.applyWeaponEnhancement(attacker: .player, target: Self.foe) == 0)
        let profile = ItemEnchantmentProfile(
            item: FormID(0x800), enchantment: .plugin(name: "base.esm", objectID: 0x801),
            sourcePlugin: "base.esm", entries: [], name: "Fiery Sword",
            castingType: .fireAndForget, delivery: .touch, type: .enchantment,
            capacity: 100, costPerUse: 10, wornRestriction: nil
        )
        let hit = WeaponEnchantmentHit(profile: profile, attacker: .player, target: Self.foe)
        #expect(part.applyWeaponEnchantment(hit) == nil)
    }

    @Test func aCoordinatorWithoutDataHasNoArchery() {
        #expect(CombatCoordinator(world: FakeCoordinatorWorld(), data: nil).archery == nil)
    }

    @Test func thePlayerGraphTakesAnEventAndAVariableWithoutATarget() {
        let world = FakeCoordinatorWorld()
        let part = CombatCoordinator(world: world, data: nil).meleeWorld
        part.writeCombatVariable(.bool(true), named: "bIsBlocking")
        #expect(part.raiseCombatEvent("blockStart", on: .player))
        #expect(world.raisedEvents == ["blockStart"])
        #expect(part.impactMaterial(of: Self.foe) == nil)
    }

    @Test func defaultBloodIsQueued() {
        let coordinator = CombatCoordinator(world: FakeCoordinatorWorld(), data: nil)
        coordinator.meleeWorld.showDefaultBlood(on: Self.foe, at: .zero, melee: true)
        #expect(coordinator.takeCommands() == [.showDefaultBlood(
            on: Self.foe,
            at: .zero,
            melee: true
        )])
    }
}
