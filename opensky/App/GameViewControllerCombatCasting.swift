// AI spell use (issue #473, roadmap item 19.10): what a fighting NPC can cast,
// and the three calls the combat loop turns a casting decision into.
//
// A satellite of `GameViewControllerCombatWorld.swift` rather than more methods
// on it, along the same seam that file already splits on: everything there is a
// plain read off something that exists, and everything here spends magicka and
// puts a spell in the air.
//
// ## The NPC path is the player's path
//
// Nothing below is a second cast loop. An NPC's spell is readied through
// `SpellbookRuntime.equip`, begun through `CasterRuntime.begin`, charged by
// `CasterRuntime.advance` and let go through `CasterRuntime.release` — the four
// calls the panel's Cast button makes for the player. What the combat layer
// supplies is only *when*, and what this file supplies is only *who*: the
// caster is the actor rather than the player, so the aim ray starts at its eye
// and the projectile leaves from there (`GameViewControllerSpellDelivery`).
//
// ## Spells arrive when the actor first thinks about casting
//
// An NPC's `SPLO` list is authored in its NPC_ and its RACE, and
// `ActorSpellBaselineResolver` reads it back out. It is granted into the
// actor's `SpellbookState` the first time the combat loop asks what that actor
// can cast, and its abilities are applied in the same pass — lazily rather than
// for every resident actor at cell build, because a cell of forty townsfolk who
// will never fight would otherwise write forty spellbook components into the
// save to say what their base records already say. The grant is idempotent, so
// an actor that fights, gives up and fights again is granted once.
//
// Documented in docs/engine/magic.md.

import AppKit
import simd

extension GameViewController {
    /// The hand an NPC casts with.
    ///
    /// The right, always. Vanilla NPCs dual-cast and hold a spell in either
    /// hand; picking one hand here is a stated simplification rather than an
    /// observation, and it is the hand a player's own attack button casts from.
    static let actorCastHand = SpellHand.right

    /// Grants `holder` its authored spell list once, and applies the abilities
    /// in it.
    ///
    /// - Returns: how many spells the grant added, which is zero on every call
    ///   after the first.
    @discardableResult
    func grantActorSpells(to holder: ActorValueHolder) -> Int {
        guard
            let runtime = casting.runtime,
            let resolver = casting.spellBaselines,
            let plugin = casting.spellPluginName,
            !casting.grantedActors.contains(holder.key)
        else { return 0 }
        casting.grantedActors.insert(holder.key)
        let baseline = resolver.baseline(for: holder.subject)
        let granted = runtime.spellbook.grant(
            runtime.spellbook.resolve(baseline.all, fromPlugin: plugin),
            to: holder
        )
        runtime.applyAbilities(on: holder)
        return granted
    }

    /// One known spell as a combat option, or nil when it is not something this
    /// build can throw at somebody.
    ///
    /// Four gates, and each refuses a different thing:
    ///
    /// * an ability or a power is not a combat spell — the first is carried
    ///   rather than cast and the second is spent once a day, which is a
    ///   resource this layer has no rule for;
    /// * a spell with no hostile effect entry is a heal or a buff, and casting
    ///   one at an enemy would be a decision nobody could read;
    /// * a delivery this build does not carry out is refused here rather than
    ///   inside the cast loop, so an actor does not spend a decision on a cast
    ///   that was always going to be counted as unimplemented;
    /// * a spell whose ETYP takes no hand cannot be readied, so there is no
    ///   hand for it to be cast from.
    func combatSpellOption(_ spell: ResolvedSpell) -> CombatSpellOption? {
        guard spell.spellType == .spell else { return nil }
        let delivery = spell.data?.delivery ?? .selfTarget
        guard delivery != .selfTarget else { return nil }
        guard
            SpellDelivery.isImplemented(delivery, castingType: spell.data?.castingType),
            spell.effects.contains(where: {
                $0.effect?.effect.data?.flags.contains(.hostile) == true
            }),
            casting.runtime?.spellbook.occupancy(of: spell, in: Self.actorCastHand) != nil
        else { return nil }
        return CombatSpellOption(
            spell: spell.key,
            cost: Float(spell.cost.cost),
            range: castReach(within: spell.data?.range ?? 0),
            chargeSeconds: max(0, spell.data?.chargeTime ?? 0),
            isConcentration: spell.data?.castingType == .concentration
        )
    }

    /// One frame of every NPC cast in flight, charged on the same clock the
    /// player's is.
    ///
    /// Without this a charge would never finish and a maintained cast would
    /// never apply: `CasterRuntime.advance` is what moves a cast through its
    /// phases, and the player's frame hook only advances the player.
    func advanceActorCasts(delta: Float) {
        guard let runtime = casting.runtime, delta > 0 else { return }
        for key in runtime.castingActors where key != .player {
            guard let holder = actorValueHolder(for: key) else { continue }
            runtime.advance(delta: delta, on: holder)
        }
    }
}

extension GameViewController {
    /// What `key` could cast right now, granting its authored spells the first
    /// time it is asked.
    func combatCasting(of key: ReferenceKey) -> CombatCastingProfile {
        guard
            combat.allowsActorCasting,
            let runtime = casting.runtime,
            let values = actorValues.runtime,
            let holder = actorValueHolder(for: key)
        else { return .none }
        grantActorSpells(to: holder)
        return CombatCastingProfile(
            magicka: values.current(of: holder).magicka,
            options: runtime.spellbook.knownSpells(of: holder)
                .compactMap { combatSpellOption($0) }
                .sorted { $0.spell < $1.spell }
        )
    }

    /// Readies `option` in the actor's hand and starts its cast.
    @discardableResult
    func beginCombatCast(_ option: CombatSpellOption, by key: ReferenceKey) -> Bool {
        guard
            let runtime = casting.runtime,
            let holder = actorValueHolder(for: key),
            (try? runtime.spellbook.equip(option.spell, in: Self.actorCastHand, on: holder))
            != nil
        else { return false }
        return runtime.begin(Self.actorCastHand, on: holder).failure == nil
    }

    /// Lets go of the cast the actor is holding.
    ///
    /// A maintained cast whose SPIT minimum duration has not elapsed answers
    /// `.ignored` and keeps running, which for the player is the release being
    /// deferred until the floor is reached. An NPC has no button still held, so
    /// the cast is dropped instead of left draining a magicka bar nothing will
    /// ever release.
    @discardableResult
    func releaseCombatCast(_ option: CombatSpellOption, by key: ReferenceKey) -> Bool {
        guard let runtime = casting.runtime, let holder = actorValueHolder(for: key)
        else { return false }
        let outcome = runtime.release(Self.actorCastHand, on: holder)
        let stillRunning = runtime.phase(of: Self.actorCastHand, on: key).isCasting
        if stillRunning {
            runtime.cancel(Self.actorCastHand, on: holder)
        }
        casting.actorCastCount += outcome.isFinished ? 1 : 0
        return outcome.isFinished
    }

    /// Drops a cast in flight: a stagger, a retreat, a fight that ended.
    func cancelCombatCast(by key: ReferenceKey) {
        guard let runtime = casting.runtime, let holder = actorValueHolder(for: key)
        else { return }
        runtime.cancel(Self.actorCastHand, on: holder)
    }
}
