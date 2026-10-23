// Banish, Command Summoned, the race changes, Werewolf Feed, Light, and Enhance Weapon:
// the world archetypes that act once or for as long as their effect runs. Quotes are
// from the Creation Kit wiki's Magic Effect page (<https://ck.uesp.net/wiki/Magic_Effect>).
// See docs/engine/magic-archetypes.md.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import simd

/// A light the Light archetype placed: on an actor while its effect runs, or at the
/// point an aimed light landed until its duration ends.
nonisolated public struct MagicLight: Equatable, Sendable {
    public enum Anchor: Equatable, Sendable {
        case actor(ReferenceKey)
        case point(SIMD3<Float>)
    }

    /// The `LIGH`.
    public let light: ReferenceKey
    public let anchor: Anchor
    /// The stored effect that holds an actor's light; zero for a point light.
    public let sequence: UInt64
    /// Seconds a point light has left. Nil while an effect holds the light.
    public var remaining: Float?

    public init(
        light: ReferenceKey,
        anchor: Anchor,
        sequence: UInt64 = 0,
        remaining: Float? = nil
    ) {
        self.light = light
        self.anchor = anchor
        self.sequence = sequence
        self.remaining = remaining
    }
}

extension MagicCoordinator {
    func performWorldArchetype(_ action: MagicWorldAction) {
        switch (action.archetype, action.phase) {
        case (.banish, .began): banish(action.target.key)
        case (.commandSummoned, .began): takeCommand(of: action.target.key, by: action.caster)
        case (.changeRace, .began): changeRace(action)
        case (.werewolfFeed, .began): world.markEaten(action.target.key)
        case (.light, .began): startLight(action)
        case (.light, .ended):
            magicLights.removeAll {
                $0.anchor == .actor(action.target.key) && $0.sequence == action.sequence
            }
        default: break
        }
    }

    /// Why `archetype` cannot act on `holder`, for the runtime's target check.
    func worldRefusal(
        _ archetype: MagicWorldArchetype, on holder: ActorValueHolder
    ) -> MagicEffectPlanFailure? {
        switch archetype {
        case .banish, .commandSummoned:
            let summoned = commanded.contains { $0.actor == holder.key && $0.kind == .summoned }
            return summoned ? nil : .wrongTarget(archetype == .banish ? .banish : .commandSummoned)
        case .werewolfFeed:
            return world.isActorDead(holder.key) ? nil : .wrongTarget(.werewolfFeed)
        case .enhanceWeapon:
            let refusal = enhanceWeaponRefusal(on: holder)
            if let refusal, holder.key == .player {
                pendingCommands.append(.notice(castNotices[
                    refusal == .noMeleeWeapon ? .enhanceWeaponNoWeapon : .enhanceWeaponEnchanted
                ]))
            }
            return refusal
        default:
            return nil
        }
    }

    // MARK: - Summons

    /// "Banishes Summoned Actors up to level <MAG>." The summon goes, and the effect that
    /// held it ends.
    private func banish(_ actor: ReferenceKey) {
        guard let index = commanded.firstIndex(where: { $0.actor == actor && $0.kind == .summoned })
        else { return }
        let summon = commanded.remove(at: index)
        world.releaseCommandedActor(summon)
        guard let holder = world.actorValueHolder(for: summon.holder) else { return }
        withEffects { $0.dispel(on: holder) { $0.sequence == summon.sequence } }
    }

    /// "Takes control of Summoned Actors up to level <MAG>." The summon keeps the time its
    /// own effect has left, as UESP's Command Daedra page notes.
    private func takeCommand(of actor: ReferenceKey, by caster: ReferenceKey?) {
        guard
            let caster,
            let index = commanded.firstIndex(where: { $0.actor == actor && $0.kind == .summoned }),
            commanded[index].caster != caster
        else { return }
        let old = commanded[index]
        commanded[index] = CommandedActor(
            actor: actor, caster: caster, kind: .summoned, holder: old.holder,
            sequence: old.sequence
        )
        world.commandActor(actor, for: caster)
    }

    // MARK: - Race and feeding

    /// "Changes the target's race to the specified race." A script changes it back, so
    /// the end of the effect leaves the race as it is.
    private func changeRace(_ action: MagicWorldAction) {
        guard
            let item = associatedItem(of: action.effect),
            let race = effects?.effects.loadOrderFormID(item)
        else { return }
        if !world.changeRace(of: action.target.key, to: race) {
            recordEffect(.raceChangeFailed(actor: world.actorName(action.target)))
        }
    }

    // MARK: - Light

    /// "Creates the specified light object." It rides the actor the effect runs on.
    private func startLight(_ action: MagicWorldAction) {
        guard let light = associatedLight(of: action.effect) else { return }
        magicLights.append(MagicLight(
            light: light, anchor: .actor(action.target.key), sequence: action.sequence
        ))
    }

    private func associatedLight(of effect: ReferenceKey) -> ReferenceKey? {
        associatedItem(of: effect).map(ReferenceKey.init(resolved:))
    }

    /// An aimed spell that met a surface: each Light entry stays at the point for its
    /// duration, as Magelight does.
    public func spellLanded(_ payload: SpellPayload, at point: SIMD3<Float>) {
        guard let store = effects?.effects else { return }
        for entry in payload.entries {
            guard
                let resolved = store.resolve(entry.effect, fromPlugin: payload.sourcePlugin),
                resolved.effect.data?.archetype == .light,
                let light = associatedLight(of: ReferenceKey(resolved: resolved.id))
            else { continue }
            magicLights.append(MagicLight(
                light: light, anchor: .point(point), remaining: Float(entry.duration)
            ))
        }
    }

    /// Ages the point lights; a light an effect holds ends with it.
    func advanceLights(delta: Float) {
        guard delta.isFinite, delta > 0 else { return }
        magicLights = magicLights.compactMap { light in
            guard let remaining = light.remaining else { return light }
            var aged = light
            aged.remaining = remaining - delta
            return remaining - delta > 0 ? aged : nil
        }
    }

    // MARK: - Enhance Weapon

    /// "Any equipped (melee) weapon receives the specified enchantment." UESP: it "does
    /// not work on enchanted or bound weapons".
    private func enhanceWeaponRefusal(on holder: ActorValueHolder) -> MagicEffectPlanFailure? {
        let weapons = meleeWeapons(of: holder)
        guard !weapons.isEmpty else { return .noMeleeWeapon }
        let owner = InventoryHolder(actor: holder)
        let bound = Set(boundWeapons(on: holder))
        let usable = weapons.filter { weapon in
            enchantmentProfile(of: weapon, on: owner) == nil && !bound.contains(weapon)
        }
        return usable.isEmpty ? .weaponEnchanted : nil
    }

    /// The equipped weapons that strike in melee: not a bow, a crossbow, or a staff.
    func meleeWeapons(of holder: ActorValueHolder) -> [FormID] {
        guard let inventory = world.inventory, let equipment = world.equipment else { return [] }
        let items = inventory.baselines.items
        return equipment.equipped(on: InventoryHolder(actor: holder)).filter { item in
            guard let kind = items.weapon(item)?.animationType else { return false }
            return ![.bow, .staff, .crossbow, .other].contains(kind)
        }
    }

    /// The weapons `holder`'s running Bound Weapon effects conjured.
    private func boundWeapons(on holder: ActorValueHolder) -> [FormID] {
        guard let runtime = effects else { return [] }
        return runtime.active(on: holder)
            .filter { runtime.rule(of: $0) == .world(.boundWeapon) }
            .compactMap { associatedItem(of: $0.effect).flatMap(runtime.effects.loadOrderFormID) }
    }

    /// A melee blow by `attacker` lands each running Enhance Weapon enchantment on
    /// `target`, scaled by its resistances like any enchanted hit. Returns the effects
    /// stored.
    @discardableResult
    public func applyWeaponEnhancement(attacker: ReferenceKey, target: ReferenceKey) -> Int {
        guard
            let runtime = effects, let store = enchantmentStore,
            let owner = world.actorValueHolder(for: attacker),
            let victim = world.actorValueHolder(for: target)
        else { return 0 }
        let enchantments = runtime.active(on: owner)
            .filter { runtime.rule(of: $0) == .world(.enhanceWeapon) }
            .compactMap { associatedItem(of: $0.effect).flatMap(store.enchantment) }
        guard !enchantments.isEmpty else { return 0 }
        return withEffects { runtime in
            enchantments.reduce(0) { stored, enchantment in
                let scaled = SpellHitApplication.scale(
                    enchantment.record.effects, fromPlugin: enchantment.sourcePlugin,
                    ignoresResistance: false, on: victim, using: runtime,
                    resistances: .documentedDefaults
                )
                return stored + runtime.apply(
                    scaled.entries, fromPlugin: enchantment.sourcePlugin,
                    source: ActiveEffectSource(
                        kind: .enchantment, record: ReferenceKey(resolved: enchantment.id)
                    ),
                    caster: attacker, on: victim
                ).count
            }
        } ?? 0
    }

    /// "Until unequipped": an actor left with no usable melee weapon loses the effect.
    func endWeaponEnhancement(on holder: ActorValueHolder) {
        guard let runtime = effects, enhanceWeaponRefusal(on: holder) != nil else { return }
        let running = runtime.active(on: holder)
            .filter { runtime.rule(of: $0) == .world(.enhanceWeapon) }
        guard !running.isEmpty else { return }
        let sequences = Set(running.map(\.sequence))
        withEffects { $0.dispel(on: holder) { sequences.contains($0.sequence) } }
    }

    /// Bound Weapon "dispels it when the duration expires or the weapon is sheathed".
    func dismissBoundWeaponsOnSheathe(of key: ReferenceKey) {
        guard let runtime = effects, let holder = world.actorValueHolder(for: key) else { return }
        let running = runtime.active(on: holder)
            .filter { runtime.rule(of: $0) == .world(.boundWeapon) }
        guard !running.isEmpty else { return }
        let sequences = Set(running.map(\.sequence))
        withEffects { $0.dispel(on: holder) { sequences.contains($0.sequence) } }
    }
}
