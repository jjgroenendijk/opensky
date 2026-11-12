// Banish, Command Summoned, the race changes, Werewolf Feed, Light, and Enhance Weapon:
// the world archetypes that act once or for as long as their effect runs. Quotes are
// from the Creation Kit wiki's Magic Effect page (<https://ck.uesp.net/wiki/Magic_Effect>).
// See docs/engine/magic-archetypes.md.

public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
public import OpenSkyMagicInterface
import simd

extension MagicCoordinator.WorldArchetypeActions {
    func performWorldArchetype(_ action: MagicWorldAction) {
        switch (action.archetype, action.phase) {
        case (.banish, .began): banish(action.target.key)
        case (.commandSummoned, .began): takeCommand(of: action.target.key, by: action.caster)
        case (.changeRace, .began): changeRace(action)
        case (.werewolfFeed, .began): coordinator.world.markEaten(action.target.key)
        case (.light, .began): startLight(action)
        case (.light, .ended):
            coordinator.magicLights.removeAll {
                $0.anchor == .actor(action.target.key) && $0.sequence == action.sequence
            }
        default: break
        }
    }

    // MARK: - Summons

    /// "Banishes Summoned Actors up to level <MAG>." The summon goes, and the effect that
    /// held it ends.
    private func banish(_ actor: ReferenceKey) {
        guard
            let index = coordinator.commanded
                .firstIndex(where: { $0.actor == actor && $0.kind == .summoned })
        else { return }
        let summon = coordinator.commanded.remove(at: index)
        coordinator.world.releaseCommandedActor(summon)
        guard let holder = coordinator.world.actorValueHolder(for: summon.holder) else { return }
        coordinator.withEffects { $0.dispel(on: holder) { $0.sequence == summon.sequence } }
    }

    /// "Takes control of Summoned Actors up to level <MAG>." The summon keeps the time its
    /// own effect has left, as UESP's Command Daedra page notes.
    private func takeCommand(of actor: ReferenceKey, by caster: ReferenceKey?) {
        guard
            let caster,
            let index = coordinator.commanded
                .firstIndex(where: { $0.actor == actor && $0.kind == .summoned }),
            coordinator.commanded[index].caster != caster
        else { return }
        let old = coordinator.commanded[index]
        coordinator.commanded[index] = CommandedActor(
            actor: actor, caster: caster, kind: .summoned, holder: old.holder,
            sequence: old.sequence
        )
        coordinator.world.commandActor(actor, for: caster)
    }

    // MARK: - Race and feeding

    /// "Changes the target's race to the specified race." A script changes it back, so
    /// the end of the effect leaves the race as it is.
    private func changeRace(_ action: MagicWorldAction) {
        guard
            let item = coordinator.associatedItem(of: action.effect),
            let race = coordinator.effects?.effects.loadOrderFormID(item)
        else { return }
        if !coordinator.world.changeRace(of: action.target.key, to: race) {
            coordinator
                .recordEffect(.raceChangeFailed(actor: coordinator.world.actorName(action.target)))
        }
    }

    // MARK: - Light

    /// "Creates the specified light object." It rides the actor the effect runs on.
    private func startLight(_ action: MagicWorldAction) {
        guard let light = associatedLight(of: action.effect) else { return }
        coordinator.magicLights.append(MagicLight(
            light: light, anchor: .actor(action.target.key), sequence: action.sequence
        ))
    }

    private func associatedLight(of effect: ReferenceKey) -> ReferenceKey? {
        coordinator.associatedItem(of: effect).map(ReferenceKey.init(resolved:))
    }

    /// An aimed spell that met a surface: each Light entry stays at the point for its
    /// duration, as Magelight does.
    public func spellLanded(_ payload: SpellPayload, at point: SIMD3<Float>) {
        guard let store = coordinator.effects?.effects else { return }
        for entry in payload.entries {
            guard
                let resolved = store.resolve(entry.effect, fromPlugin: payload.sourcePlugin),
                resolved.effect.data?.archetype == .light,
                let light = associatedLight(of: ReferenceKey(resolved: resolved.id))
            else { continue }
            coordinator.magicLights.append(MagicLight(
                light: light, anchor: .point(point), remaining: Float(entry.duration)
            ))
        }
    }

    /// Ages the point lights; a light an effect holds ends with it.
    func advanceLights(delta: Float) {
        guard delta.isFinite, delta > 0 else { return }
        coordinator.magicLights = coordinator.magicLights.compactMap { light in
            guard let remaining = light.remaining else { return light }
            var aged = light
            aged.remaining = remaining - delta
            return remaining - delta > 0 ? aged : nil
        }
    }

    // MARK: - Enhance Weapon

    /// A melee blow by `attacker` lands each running Enhance Weapon enchantment on
    /// `target`, scaled by its resistances like any enchanted hit. Returns the effects
    /// stored.
    @discardableResult
    public func applyWeaponEnhancement(attacker: ReferenceKey, target: ReferenceKey) -> Int {
        guard
            let runtime = coordinator.effects, let store = coordinator.enchantmentStore,
            let owner = coordinator.world.actorValueHolder(for: attacker),
            let victim = coordinator.world.actorValueHolder(for: target)
        else { return 0 }
        let enchantments = runtime.active(on: owner)
            .filter { runtime.rule(of: $0) == .world(.enhanceWeapon) }
            .compactMap { coordinator.associatedItem(of: $0.effect).flatMap(store.enchantment) }
        guard !enchantments.isEmpty else { return 0 }
        return coordinator.withEffects { runtime in
            enchantments.reduce(0) { stored, enchantment in
                let scaled = SpellHitApplication.scale(
                    enchantment.record.effects, source: (enchantment.sourcePlugin, false),
                    on: victim, using: runtime,
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
}
