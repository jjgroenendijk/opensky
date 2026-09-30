// The world a fighting caster runs in: one NPC, one player, a spellbook, a
// cast loop, and a real `ActiveEffectRuntime`, headless. It does what the
// app's casting bridge does, so `CombatLoopCastingTests` tests the pipeline.
// Both test bundles use it: synthetic `SpellbookFixture` records, or the
// install's stores. Nothing here is extracted game data.

import Foundation
@testable import OpenSkyActors
@testable import OpenSkyActorsInterface
@testable import OpenSkyBehavior
@testable import OpenSkyCombat
@testable import OpenSkyCombatInterface
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyMagic
@testable import OpenSkyMagicInterface
import OpenSkyMagicTesting
@testable import OpenSkyPhysics
@testable import OpenSkyWorld
@testable import OpenSkyWorldState
import simd

@MainActor
public final class CombatCastingChain {
    public static let caster = ReferenceKey.plugin(name: "base.esm", objectID: 0x0901)
    public static let casterBase = FormID(0x0000_0F01)

    public let spellbook: SpellbookRuntime
    public let values: ActorValueRuntime
    public let caster: CasterRuntime
    public let combat: CombatLoopRuntime
    public var effects: ActiveEffectRuntime

    /// Where the two stand. The player never moves in these cases; the caster
    /// is placed where a case wants it and stays there, because the mover is
    /// 16.4's and a fake that walked would be simulating it.
    public var playerFeet = SIMD3<Float>()
    public var casterFeet = SIMD3<Float>(1200, 0, 0)
    public var casterIsDead = false
    public var hostility: [ReferenceKey: ActorHostility] = [CombatCastingChain.caster: .hostile]

    /// Every projectile a cast put in the air, and every spell that landed.
    public private(set) var firedProjectiles: [SpellPayload] = []
    public private(set) var spellHits: [SpellHit] = []
    public private(set) var resumedPackages: [ReferenceKey] = []

    /// Over `SpellbookFixture`'s synthetic records.
    public convenience init() throws {
        let index = try SpellbookFixture.index()
        let store = WorldStateStore()
        let values = SpellbookFixture.values(store: store)
        try self.init(
            spellbook: SpellbookFixture.runtime(store: store).0,
            values: values,
            effects: ActiveEffectRuntime(
                values: values,
                effects: SpellbookFixture.effectStore(index: index),
                conditionRegistry: .standard
            )
        )
    }

    /// Over whatever records the caller indexed, which is how the real-data
    /// suite drives the same pipeline against the install.
    public init(
        spellbook: SpellbookRuntime,
        values: ActorValueRuntime,
        effects: ActiveEffectRuntime
    ) {
        self.spellbook = spellbook
        self.values = values
        self.effects = effects
        caster = CasterRuntime(spellbook: spellbook, values: values)
        combat = CombatLoopRuntime(settings: .synthetic)
        combat.behaviorSettings = CombatBehaviorSettings(blockChance: 0, castChance: 1)
        caster.attach(world: self)
        combat.attach(world: self)
    }

    /// The caster's holder, which is an actor rather than the player so the
    /// player's own damage cap never enters the arithmetic.
    public var casterHolder: ActorValueHolder {
        ActorValueHolder(key: Self.caster, subject: .actor(base: Self.casterBase), cell: nil)
    }

    /// Teaches the caster one fixture spell.
    public func teach(_ objectID: UInt32) {
        spellbook.learn(SpellbookFixture.key(objectID), on: casterHolder)
    }

    /// Grants a whole authored list, which is what the combat loop does the
    /// first time an actor is asked what it can cast.
    public func grant(_ spells: [ReferenceKey]) {
        spellbook.grant(spells, to: casterHolder)
    }

    /// Every option the caster would have from where it is standing.
    public var options: [CombatSpellOption] {
        combatCasting(of: Self.caster).options
    }

    /// Advances the fight and every cast in flight by `seconds`, in the fixed
    /// steps the runtime itself uses.
    public func advance(seconds: Float) {
        var elapsed: Float = 0
        while elapsed < seconds {
            let step = CombatLoopRuntime.fixedStepSeconds
            combat.advance(by: step)
            caster.advance(delta: step, on: casterHolder)
            elapsed += step
        }
    }

    public var playerHealth: Float {
        values.current(of: .player).health
    }

    public var casterMagicka: Float {
        values.current(of: casterHolder).magicka
    }
}

// MARK: - The fight

extension CombatCastingChain: CombatLoopWorld {
    public var combatPlayer: MeleeAttacker {
        MeleeAttacker(key: .player, feet: playerFeet, facing: 0)
    }

    public func combatActors() -> [CombatActorObservation] {
        [CombatActorObservation(
            key: Self.caster, feet: casterFeet, isDead: casterIsDead, name: "Caster"
        )]
    }

    public func combatHostility(of key: ReferenceKey) -> ActorHostility {
        hostility[key] ?? .neutral
    }

    @discardableResult
    public func setCombatHostility(_ value: ActorHostility, on key: ReferenceKey) -> Bool {
        guard hostility[key] != value else { return false }
        hostility[key] = value
        return true
    }

    @discardableResult
    public func applyCombatDamage(_ amount: Float, to key: ReferenceKey) -> Bool {
        guard amount > 0 else { return false }
        values.damage(.health, by: amount, on: holder(for: key))
        return true
    }

    public func combatBlock(of key: ReferenceKey) -> MeleeBlockKind? {
        combat.blockKind(of: key)
    }

    public func combatAwareness(
        of observer: ReferenceKey, toward target: ReferenceKey
    ) -> CombatAwareness {
        .detected(at: playerFeet)
    }

    public func combatHealthFraction(of key: ReferenceKey) -> Float {
        1
    }

    public func combatWeapon(of key: ReferenceKey) -> MeleeWeaponProfile {
        .unarmed
    }

    public func combatCasting(of key: ReferenceKey) -> CombatCastingProfile {
        guard key == Self.caster else { return .none }
        return CombatCastingProfile(
            magicka: casterMagicka,
            options: spellbook.knownSpells(of: casterHolder).compactMap(Self.option)
        )
    }

    /// One known spell as a combat option, on the same four gates the app's
    /// bridge applies: a spell rather than an ability or a power, delivered
    /// away from the caster, hostile, and something this build carries out.
    public static func option(for spell: ResolvedSpell) -> CombatSpellOption? {
        let delivery = spell.data?.delivery ?? .selfTarget
        guard
            spell.spellType == .spell,
            delivery != .selfTarget,
            SpellDelivery.isImplemented(delivery, castingType: spell.data?.castingType),
            spell.effects.contains(where: {
                $0.effect?.effect.data?.flags.contains(.hostile) == true
            })
        else { return nil }
        let range = spell.data?.range ?? 0
        return CombatSpellOption(
            spell: spell.key,
            cost: Float(spell.cost.cost),
            range: range > 0 ? range : 4000,
            chargeSeconds: max(0, spell.data?.chargeTime ?? 0),
            isConcentration: spell.data?.castingType == .concentration
        )
    }

    @discardableResult
    public func beginCombatCast(_ option: CombatSpellOption, by key: ReferenceKey) -> Bool {
        guard (try? spellbook.equip(option.spell, in: .right, on: casterHolder)) != nil
        else { return false }
        return caster.begin(.right, on: casterHolder).failure == nil
    }

    @discardableResult
    public func releaseCombatCast(_ option: CombatSpellOption, by key: ReferenceKey) -> Bool {
        let outcome = caster.release(.right, on: casterHolder)
        if caster.phase(of: .right, on: key).isCasting {
            caster.cancel(.right, on: casterHolder)
        }
        return outcome.isFinished
    }

    public func cancelCombatCast(by key: ReferenceKey) {
        caster.cancel(.right, on: casterHolder)
    }

    @discardableResult
    public func moveCombatActor(_ key: ReferenceKey, to point: SIMD3<Float>) -> Bool {
        true
    }

    public func stopCombatMovement(of key: ReferenceKey) {}

    public func resumeCombatPackage(for key: ReferenceKey) {
        resumedPackages.append(key)
    }

    @discardableResult
    public func raiseCombatEvent(_ name: String, on target: ReferenceKey?) -> Bool {
        false
    }

    public func writeCombatVariable(_ value: BehaviorVariableValue, named name: String) {}

    @discardableResult
    public func playCombatClip(_ clip: CombatActorClip, on key: ReferenceKey) -> Bool {
        false
    }

    public var combatTransients: CombatTransientCounts {
        .none
    }

    @discardableResult
    public func trimCombatTransients(to limits: CombatTransientLimits) -> CombatTransientCounts {
        .none
    }

    public func despawnCombatTransients() {}

    public func setCombatMusicActive(_ active: Bool) {}

    /// The holder behind a key: the player is the player, and everybody else is
    /// the one caster this chain has.
    public func holder(for key: ReferenceKey) -> ActorValueHolder {
        key == .player ? .player : casterHolder
    }
}

// MARK: - The cast

extension CombatCastingChain: CasterWorld {
    public var castingGameDay: Int32 {
        0
    }

    public func applyCastEffects(
        _ entries: [MagicItemEffect],
        fromPlugin pluginName: String,
        source: ActiveEffectSource,
        caster: ReferenceKey,
        on target: ActorValueHolder
    ) -> Int {
        effects.apply(
            entries, fromPlugin: pluginName, source: source, caster: caster, on: target
        ).count
    }

    /// Lands what the cast fired at its target. The flight is not simulated:
    /// `ProjectileSpellTests` covers it. Launch and landing are both recorded.
    @discardableResult
    public func fireSpellProjectile(_ payload: SpellPayload) -> Bool {
        firedProjectiles.append(payload)
        let aim = aimedSpellTarget(within: 0, for: payload.caster)
        let targets = SpellHitTargeting.targets(
            of: payload,
            at: aim.position,
            struck: aim.target,
            candidates: aim.candidates,
            excluding: payload.caster
        )
        guard !targets.isEmpty else { return true }
        applySpellHit(SpellHit(payload: payload, targets: targets))
        return true
    }

    /// The caster's aim ray reaches the player, which is what a fight of one
    /// NPC against one player means. The position is the player's feet, so an
    /// area entry measures its radius from where the player is standing.
    public func aimedSpellTarget(within range: Float, for caster: ReferenceKey) -> SpellAim {
        SpellAim(
            target: .player,
            position: playerFeet,
            candidates: [MeleeTarget(key: .player, feet: playerFeet, capsule: .standard)]
        )
    }

    @discardableResult
    public func applySpellHit(_ hit: SpellHit) -> SpellHitReport {
        spellHits.append(hit)
        var holders: [ReferenceKey: ActorValueHolder] = [:]
        for target in hit.targets {
            holders[target.key] = holder(for: target.key)
        }
        return SpellHitApplication.apply(hit, holders: holders, using: &effects)
    }
}
