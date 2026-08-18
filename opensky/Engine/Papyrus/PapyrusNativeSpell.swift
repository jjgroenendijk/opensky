// The spell natives (issue #474, roadmap item 19.11): the `Actor` spell family
// and `Spell.Cast`, over 19.6's active effects and 19.7's spellbook.
//
// Policy is the `Actor` family's, unchanged: `self` arrives as
// `PapyrusNativeCall.receiver` and becomes a `ReferenceKey`; a headless
// runtime, a handle with no world identity, or a session with no spellbook is a
// failure with a reason rather than a guess, and the interpreter substitutes
// the call's declared default so the script keeps running.
//
// The eleven registered here were chosen by counting what the shipped scripts
// actually call, not by taste: `PexNativeCensus` over the vanilla corpus ranks
// `Actor.RemoveSpell` at 311 call sites, `Actor.AddSpell` at 278 and
// `Spell.Cast` at 277, and the per-native counts are in
// docs/engine/papyrus-vm.md.
//
// ## Latency
//
// None of these is latent. The Creation Kit wiki declares every one of them a
// plain `native` with no `Global`/latent marker, and says of the cast outright:
// "This function casts the spell instantaneously."
// (<https://ck.uesp.net/wiki/Cast_-_Spell>) So each returns on the same call
// the script made and none of them suspends the frame.
//
// ## What is deliberately absent, and why
//
// `Actor.DoCombatSpellApply` (26 call sites) is a combat-AI request rather than
// a cast: it asks the actor's combat controller to work the spell into what it
// is already doing, and 19.10's caster AI chooses its own spells. Registering
// it as an immediate cast would make an NPC fire through its own decision loop.
// `Spell.RemoteCast`, `Spell.Preload` and `Spell.Unload` are absent with the
// asset lifecycle they name. The whole `ActiveMagicEffect` script is absent
// because no script archetype MGEF runs yet (tallied in 19.6), so there is no
// receiver for one of its methods to be about.

import Foundation

nonisolated extension PapyrusNativeFunctions {
    static func installSpell(into registry: inout PapyrusNativeRegistry) {
        installSpellKnowledge(into: &registry)
        installSpellEquip(into: &registry)
        installSpellEffects(into: &registry)
        installSpellCast(into: &registry)
    }

    /// `bool AddSpell(Spell akSpell, bool abVerbose = true)`,
    /// `bool RemoveSpell(Spell akSpell)` and `bool HasSpell(Form akForm)`.
    ///
    /// "Adds the specified spell to this actor ... True on success."
    /// (<https://ck.uesp.net/wiki/AddSpell_-_Actor>) `abVerbose` only suppresses
    /// a UI message, and there is no spell-added message to suppress yet, so
    /// the argument is accepted and ignored rather than refused.
    ///
    /// "Removes the specified spell from this actor."
    /// (<https://ck.uesp.net/wiki/RemoveSpell_-_Actor>) The same page records a
    /// vanilla quirk OpenSky does not reproduce: a spell inherited from the
    /// ActorBase or Race is not actually removed but "will still return true in
    /// such cases". Here a spell granted from an actor's `SPLO` list is an
    /// ordinary known spell and removing it removes it. Reproducing a
    /// documented lie would make every correct script wrong.
    ///
    /// "Checks to see if this actor has the given Spell or Shout ... This
    /// function only detects whether the actor knows a spell."
    /// (<https://ck.uesp.net/wiki/HasSpell_-_Actor>) A shout is a SHOU record
    /// no store here carries, so it answers false rather than failing: "this
    /// actor does not know that" is the honest answer for a record the
    /// spellbook can never contain.
    private static func installSpellKnowledge(
        into registry: inout PapyrusNativeRegistry
    ) {
        registry.register(PapyrusNativeFunction(
            scriptName: "Actor",
            functionName: "AddSpell"
        ) { call, context in
            spellTarget(call, context) { actor, spell in
                .returned(.boolean(actor.world.addSpell(spell, to: actor.key)))
            }
        })
        registry.register(PapyrusNativeFunction(
            scriptName: "Actor",
            functionName: "RemoveSpell"
        ) { call, context in
            spellTarget(call, context) { actor, spell in
                .returned(.boolean(actor.world.removeSpell(spell, from: actor.key)))
            }
        })
        registry.register(PapyrusNativeFunction(
            scriptName: "Actor",
            functionName: "HasSpell"
        ) { call, context in
            spellState(call, context) { state, spell in
                .returned(.boolean(state.knownSpells.contains(spell)))
            }
        })
    }

    /// `EquipSpell(Spell akSpell, int aiSource)`,
    /// `UnequipSpell(Spell akSpell, int aiSource)` and
    /// `Spell GetEquippedSpell(int aiSource)`.
    ///
    /// "Forces the actor to equip the specified spell in the specified source
    /// ... 0: Left hand, 1: Right hand, 2: Voice (use this for Powers)"
    /// (<https://ck.uesp.net/wiki/EquipSpell_-_Actor>), and the same numbering
    /// on the unequip and read pages. OpenSky readies spells into two hands and
    /// has no voice slot, so sources 2 and 3 are a tallied failure rather than
    /// a silent no-op.
    ///
    /// The equip returns nothing in Papyrus; the bridge still answers whether
    /// it happened, so a refusal is counted rather than invisible.
    private static func installSpellEquip(into registry: inout PapyrusNativeRegistry) {
        registry.register(PapyrusNativeFunction(
            scriptName: "Actor",
            functionName: "EquipSpell"
        ) { call, context in
            spellSource(call, context) { actor, spell, source in
                guard actor.world.equipSpell(spell, source: source, on: actor.key) else {
                    return failure(call, "EquipSpell could not ready that spell")
                }
                return .returned(.none)
            }
        })
        registry.register(PapyrusNativeFunction(
            scriptName: "Actor",
            functionName: "UnequipSpell"
        ) { call, context in
            spellSource(call, context) { actor, spell, source in
                actor.world.unequipSpell(spell, source: source, on: actor.key)
                return .returned(.none)
            }
        })
        registry.register(PapyrusNativeFunction(
            scriptName: "Actor",
            functionName: "GetEquippedSpell"
        ) { call, context in
            guard let actor = actorTarget(call, context) else {
                return needsActor(call)
            }
            guard
                let source = castingSource(call, at: 0),
                let hand = source.hand
            else {
                return failure(call, "GetEquippedSpell reads the two hands alone")
            }
            guard let state = actor.world.spellState(for: actor.key) else {
                return needsSpellbook(call)
            }
            guard let spell = state.handSpells[hand] else {
                return .returned(.none)
            }
            return .returned(handle(spell, in: actor.world))
        })
    }

    /// `bool HasMagicEffect(MagicEffect akEffect)`,
    /// `bool HasMagicEffectWithKeyword(Keyword akKeyword)`,
    /// `bool DispelSpell(Spell akSpell)` and `DispelAllSpells()`.
    ///
    /// "Checks to see if this actor is currently being affected by the given
    /// Magic Effect." (<https://ck.uesp.net/wiki/HasMagicEffect_-_Actor>) and
    /// the keyword variant on
    /// (<https://ck.uesp.net/wiki/HasMagicEffectWithKeyword_-_Actor>). Both
    /// pages note the vanilla answer ignores whether the effect's own condition
    /// holds; OpenSky stores only effects that were applied, so it answers the
    /// narrower question — the same difference the condition functions carry,
    /// recorded in docs/formats/conditions.md.
    ///
    /// "Will dispel all magic effects from this actor that came from the given
    /// spell ... True if at least one effect was dispelled from the actor."
    /// (<https://ck.uesp.net/wiki/DispelSpell_-_Actor>)
    private static func installSpellEffects(into registry: inout PapyrusNativeRegistry) {
        registry.register(PapyrusNativeFunction(
            scriptName: "Actor",
            functionName: "HasMagicEffect"
        ) { call, context in
            spellState(call, context) { state, effect in
                .returned(.boolean(state.activeEffects.contains(effect)))
            }
        })
        registry.register(PapyrusNativeFunction(
            scriptName: "Actor",
            functionName: "HasMagicEffectWithKeyword"
        ) { call, context in
            spellState(call, context) { state, keyword in
                .returned(.boolean(state.effectKeywords.contains(keyword)))
            }
        })
        registry.register(PapyrusNativeFunction(
            scriptName: "Actor",
            functionName: "DispelSpell"
        ) { call, context in
            spellTarget(call, context) { actor, spell in
                .returned(.boolean(actor.world.dispelSpell(spell, on: actor.key) > 0))
            }
        })
        registry.register(PapyrusNativeFunction(
            scriptName: "Actor",
            functionName: "DispelAllSpells"
        ) { call, context in
            guard let actor = actorTarget(call, context) else {
                return needsActor(call)
            }
            actor.world.dispelAllSpells(on: actor.key)
            return .returned(.none)
        })
    }

    /// `Cast(ObjectReference akSource, ObjectReference akTarget = None)`.
    ///
    /// "Casts this spell from the specified object reference, optionally toward
    /// a target object reference ... This function casts the spell
    /// instantaneously." (<https://ck.uesp.net/wiki/Cast_-_Spell>) The receiver
    /// is the SPEL rather than the caster, which is why this is the one native
    /// here that reads its subject out of `call.receiver` and its actor out of
    /// argument 0.
    ///
    /// `akTarget` is genuinely optional and defaults to `None`, in which case
    /// the cast follows the caster's own aim the way a player's does.
    private static func installSpellCast(into registry: inout PapyrusNativeRegistry) {
        registry.register(PapyrusNativeFunction(
            scriptName: "Spell",
            functionName: "Cast"
        ) { call, context in
            guard
                let world = context.world,
                let receiver = call.receiver,
                let spell = world.referenceKey(for: receiver)
            else {
                return failure(call, "Cast needs a world runtime and a spell receiver")
            }
            guard
                let source = objectArgument(call, at: 0),
                let caster = world.referenceKey(for: source)
            else {
                return failure(call, "Cast needs an object reference to cast from")
            }
            let target = objectArgument(call, at: 1)
                .flatMap { world.referenceKey(for: $0) }
            guard world.castSpell(spell, from: caster, at: target) else {
                return failure(call, "Cast has no caster runtime or no such spell")
            }
            return .returned(.none)
        })
    }

    // MARK: - Shared

    /// An `Actor` native whose argument 0 is a form: resolve the receiver and
    /// the argument, then run `body`.
    private static func spellTarget(
        _ call: PapyrusNativeCall,
        _ context: PapyrusNativeContext,
        body: ((world: PapyrusWorldAccess, key: ReferenceKey), ReferenceKey)
            -> PapyrusNativeResult
    ) -> PapyrusNativeResult {
        guard let actor = actorTarget(call, context) else {
            return needsActor(call)
        }
        guard
            let handle = objectArgument(call, at: 0),
            let form = actor.world.referenceKey(for: handle)
        else {
            return failure(call, "\(call.functionName) needs a form argument")
        }
        return body(actor, form)
    }

    /// An `Actor` native that reads one observation and compares argument 0
    /// against it.
    private static func spellState(
        _ call: PapyrusNativeCall,
        _ context: PapyrusNativeContext,
        body: (PapyrusSpellState, ReferenceKey) -> PapyrusNativeResult
    ) -> PapyrusNativeResult {
        spellTarget(call, context) { actor, form in
            guard let state = actor.world.spellState(for: actor.key) else {
                return needsSpellbook(call)
            }
            return body(state, form)
        }
    }

    /// An `Actor` native taking a spell and a casting source.
    private static func spellSource(
        _ call: PapyrusNativeCall,
        _ context: PapyrusNativeContext,
        body: ((world: PapyrusWorldAccess, key: ReferenceKey), ReferenceKey, CastingSource)
            -> PapyrusNativeResult
    ) -> PapyrusNativeResult {
        spellTarget(call, context) { actor, spell in
            guard let source = castingSource(call, at: 1) else {
                return failure(call, "\(call.functionName) needs a casting source")
            }
            return body(actor, spell, source)
        }
    }

    /// Argument `index` as a casting source, or nil when it is missing or names
    /// no documented source.
    static func castingSource(
        _ call: PapyrusNativeCall,
        at index: Int
    ) -> CastingSource? {
        integer(call, at: index).flatMap(CastingSource.init(rawValue:))
    }

    /// One record identity as the object value a script compares against, or
    /// Papyrus `None` when no handle can be minted for it.
    static func handle(
        _ key: ReferenceKey,
        in world: PapyrusWorldAccess
    ) -> PapyrusValue {
        world.objectHandle(for: key).map(PapyrusValue.object) ?? .none
    }

    /// The single failure a spell native returns when the session runs no
    /// spellbook — a synthetic scene with no SPEL index, where inventing an
    /// empty spellbook would read as an actor who has learned nothing.
    static func needsSpellbook(_ call: PapyrusNativeCall) -> PapyrusNativeResult {
        failure(
            call,
            "\(call.functionName) needs a session with a spellbook runtime"
        )
    }
}
