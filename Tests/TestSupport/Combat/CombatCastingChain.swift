// The world a fighting caster runs over (issue #473, roadmap item 19.10): one
// NPC, one player, one spellbook, one cast loop and one effect runtime, with no
// renderer and no window.
//
// Everything the app's own casting bridge does, done here over synthetic
// records: an actor's known spells become combat options, a chosen option is
// readied and begun through `CasterRuntime`, the charge is advanced on the same
// delta the fight is stepped with, and a released cast delivers through the
// 19.8 path into a real `ActiveEffectRuntime`. That is what makes
// `CombatLoopCastingTests` an assertion about the pipeline rather than about a
// fake that agreed with it.
//
// In `openskyTestSupport` because both test bundles drive it: the synthetic
// suite hands it `SpellbookFixture`'s records, and the real-data suite hands it
// the install's own stores and a pinned vanilla caster's spell list. The two
// then assert the same pipeline over different records rather than over two
// harnesses that could drift apart.
//
// The synthetic records are built in code (`SpellbookFixture`) — never extracted
// game files (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky
import simd

@MainActor
final class CombatCastingChain {
    static let caster = ReferenceKey.plugin(name: "base.esm", objectID: 0x0901)
    static let casterBase = FormID(0x0000_0F01)

    let store: WorldStateStore
    let spellbook: SpellbookRuntime
    let values: ActorValueRuntime
    let caster: CasterRuntime
    let combat: CombatLoopRuntime
    var effects: ActiveEffectRuntime

    /// Where the two stand. The player never moves in these cases; the caster
    /// is placed where a case wants it and stays there, because the mover is
    /// 16.4's and a fake that walked would be simulating it.
    var playerFeet = SIMD3<Float>()
    var casterFeet = SIMD3<Float>(1200, 0, 0)
    var casterIsDead = false
    var hostility: [ReferenceKey: ActorHostility] = [CombatCastingChain.caster: .hostile]

    /// Every projectile a cast put in the air, and every spell that landed.
    private(set) var firedProjectiles: [SpellPayload] = []
    private(set) var spellHits: [SpellHit] = []
    private(set) var resumedPackages: [ReferenceKey] = []

    /// Over `SpellbookFixture`'s synthetic records.
    convenience init() throws {
        let index = try SpellbookFixture.index()
        let store = WorldStateStore()
        let values = SpellbookFixture.values(store: store)
        try self.init(
            store: store,
            spellbook: SpellbookFixture.runtime(store: store).0,
            values: values,
            effects: ActiveEffectRuntime(
                values: values,
                effects: SpellbookFixture.effectStore(index: index)
            )
        )
    }

    /// Over whatever records the caller indexed, which is how the real-data
    /// suite drives the same pipeline against the install.
    init(
        store: WorldStateStore,
        spellbook: SpellbookRuntime,
        values: ActorValueRuntime,
        effects: ActiveEffectRuntime
    ) {
        self.store = store
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
    var casterHolder: ActorValueHolder {
        ActorValueHolder(key: Self.caster, subject: .actor(base: Self.casterBase), cell: nil)
    }

    /// Teaches the caster one fixture spell.
    func teach(_ objectID: UInt32) {
        spellbook.learn(SpellbookFixture.key(objectID), on: casterHolder)
    }

    /// Grants a whole authored list, which is what the combat loop does the
    /// first time an actor is asked what it can cast.
    func grant(_ spells: [ReferenceKey]) {
        spellbook.grant(spells, to: casterHolder)
    }

    /// Every option the caster would have from where it is standing.
    var options: [CombatSpellOption] {
        combatCasting(of: Self.caster).options
    }

    /// Advances the fight and every cast in flight by `seconds`, in the fixed
    /// steps the runtime itself uses.
    func advance(seconds: Float) {
        var elapsed: Float = 0
        while elapsed < seconds {
            let step = CombatLoopRuntime.fixedStepSeconds
            combat.advance(by: step)
            caster.advance(delta: step, on: casterHolder)
            elapsed += step
        }
    }

    var playerHealth: Float {
        values.current(of: .player).health
    }

    var casterMagicka: Float {
        values.current(of: casterHolder).magicka
    }
}

// MARK: - The fight

extension CombatCastingChain: CombatLoopWorld {
    var combatPlayer: MeleeAttacker {
        MeleeAttacker(key: .player, feet: playerFeet, facing: 0)
    }

    func combatActors() -> [CombatActorObservation] {
        [CombatActorObservation(
            key: Self.caster, feet: casterFeet, isDead: casterIsDead, name: "Caster"
        )]
    }

    func combatHostility(of key: ReferenceKey) -> ActorHostility {
        hostility[key] ?? .neutral
    }

    @discardableResult
    func setCombatHostility(_ value: ActorHostility, on key: ReferenceKey) -> Bool {
        guard hostility[key] != value else { return false }
        hostility[key] = value
        return true
    }

    @discardableResult
    func applyCombatDamage(_ amount: Float, to key: ReferenceKey) -> Bool {
        guard amount > 0 else { return false }
        values.damage(.health, by: amount, on: holder(for: key))
        return true
    }

    func combatBlock(of key: ReferenceKey) -> MeleeBlockKind? {
        combat.blockKind(of: key)
    }

    func combatAwareness(
        of observer: ReferenceKey, toward target: ReferenceKey
    ) -> CombatAwareness {
        .detected(at: playerFeet)
    }

    func combatHealthFraction(of key: ReferenceKey) -> Float {
        1
    }

    func combatWeapon(of key: ReferenceKey) -> MeleeWeaponProfile {
        .unarmed
    }

    func combatCasting(of key: ReferenceKey) -> CombatCastingProfile {
        guard key == Self.caster else { return .none }
        return CombatCastingProfile(
            magicka: casterMagicka,
            options: spellbook.knownSpells(of: casterHolder).compactMap(Self.option)
        )
    }

    /// One known spell as a combat option, on the same four gates the app's
    /// bridge applies: a spell rather than an ability or a power, delivered
    /// away from the caster, hostile, and something this build carries out.
    static func option(for spell: ResolvedSpell) -> CombatSpellOption? {
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
    func beginCombatCast(_ option: CombatSpellOption, by key: ReferenceKey) -> Bool {
        guard (try? spellbook.equip(option.spell, in: .right, on: casterHolder)) != nil
        else { return false }
        return caster.begin(.right, on: casterHolder).failure == nil
    }

    @discardableResult
    func releaseCombatCast(_ option: CombatSpellOption, by key: ReferenceKey) -> Bool {
        let outcome = caster.release(.right, on: casterHolder)
        if caster.phase(of: .right, on: key).isCasting {
            caster.cancel(.right, on: casterHolder)
        }
        return outcome.isFinished
    }

    func cancelCombatCast(by key: ReferenceKey) {
        caster.cancel(.right, on: casterHolder)
    }

    @discardableResult
    func moveCombatActor(_ key: ReferenceKey, to point: SIMD3<Float>) -> Bool {
        true
    }

    func stopCombatMovement(of key: ReferenceKey) {}

    func resumeCombatPackage(for key: ReferenceKey) {
        resumedPackages.append(key)
    }

    @discardableResult
    func raiseCombatEvent(_ name: String, on target: ReferenceKey?) -> Bool {
        false
    }

    func writeCombatVariable(_ value: BehaviorVariableValue, named name: String) {}

    @discardableResult
    func playCombatClip(_ clip: CombatActorClip, on key: ReferenceKey) -> Bool {
        false
    }

    var combatTransients: CombatTransientCounts {
        .none
    }

    @discardableResult
    func trimCombatTransients(to limits: CombatTransientLimits) -> CombatTransientCounts {
        .none
    }

    func despawnCombatTransients() {}

    func setCombatMusicActive(_ active: Bool) {}

    /// The holder behind a key: the player is the player, and everybody else is
    /// the one caster this chain has.
    func holder(for key: ReferenceKey) -> ActorValueHolder {
        key == .player ? .player : casterHolder
    }
}

// MARK: - The cast

extension CombatCastingChain: CasterWorld {
    var castingGameDay: Int32 {
        0
    }

    func applyCastEffects(
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

    /// Lands what the cast fired, at the target it was aimed at.
    ///
    /// The flight itself is not integrated here and does not need to be:
    /// `ProjectileSpellTests` owns the PROJ-driven trajectory and the impact
    /// query over the same `ProjectileRuntime` an arrow flies through, and what
    /// this chain is about is whether a fighting NPC's decision produces a
    /// payload that damages who it was aimed at. Both the launch and the
    /// landing are recorded, so a case can assert on either.
    @discardableResult
    func fireSpellProjectile(_ payload: SpellPayload) -> Bool {
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
        applySpellHit(SpellHit(payload: payload, position: aim.position, targets: targets))
        return true
    }

    /// The caster's aim ray reaches the player, which is what a fight of one
    /// NPC against one player means. The position is the player's feet, so an
    /// area entry measures its radius from where the player is standing.
    func aimedSpellTarget(within range: Float, for caster: ReferenceKey) -> SpellAim {
        SpellAim(
            target: .player,
            position: playerFeet,
            candidates: [MeleeTarget(key: .player, feet: playerFeet, capsule: .standard)]
        )
    }

    @discardableResult
    func applySpellHit(_ hit: SpellHit) -> SpellHitReport {
        spellHits.append(hit)
        var holders: [ReferenceKey: ActorValueHolder] = [:]
        for target in hit.targets {
            holders[target.key] = holder(for: target.key)
        }
        return SpellHitApplication.apply(hit, holders: holders, using: &effects)
    }
}
