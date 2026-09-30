// The spell natives: the `Actor` spell family and `Spell.Cast`, chosen by call
// counts over the vanilla scripts. None is latent. A missing world or spellbook
// is a failure with a reason.
//
// Documented in docs/engine/papyrus-spell-natives.md, with the natives left out on purpose.

import Foundation
import OpenSkyFormatsESM
import OpenSkyMagicInterface
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions {
    public static func installSpell(into registry: inout PapyrusNativeRegistry) {
        installSpellKnowledge(into: &registry)
        installSpellEquip(into: &registry)
        installSpellEffects(into: &registry)
        installSpellCast(into: &registry)
    }

    /// `bool AddSpell(Spell akSpell, bool abVerbose = true)`,
    /// `bool RemoveSpell(Spell akSpell)` and `bool HasSpell(Form akForm)`.
    /// `abVerbose` is ignored, because there is no spell-added message. A shout is
    /// never in the spellbook, so `HasSpell` answers false for one.
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
    /// `Spell GetEquippedSpell(int aiSource)`. There is no voice slot, so sources
    /// 2 and 3 are tallied failures. The bridge reports each equip, so a refusal
    /// is counted.
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
    /// `bool DispelSpell(Spell akSpell)` and `DispelAllSpells()`. Only applied
    /// effects are stored, so the checks answer a narrower question than the game
    /// (docs/engine/condition-functions.md).
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

    /// `Cast(ObjectReference akSource, ObjectReference akTarget = None)`
    /// (<https://ck.uesp.net/wiki/Cast_-_Spell>). The receiver is the SPEL and the
    /// caster is argument 0. With no target, the cast follows the caster's aim.
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
        body: ((world: any PapyrusWorldBridge, key: ReferenceKey), ReferenceKey)
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
        body: ((world: any PapyrusWorldBridge, key: ReferenceKey), ReferenceKey, CastingSource)
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
    public static func castingSource(
        _ call: PapyrusNativeCall,
        at index: Int
    ) -> CastingSource? {
        integer(call, at: index).flatMap(CastingSource.init(rawValue:))
    }

    /// One record identity as the object value a script compares against, or
    /// Papyrus `None` when no handle can be minted for it.
    public static func handle(
        _ key: ReferenceKey,
        in world: any PapyrusWorldBridge
    ) -> PapyrusValue {
        world.objectHandle(for: key).map(PapyrusValue.object) ?? .none
    }

    /// The single failure a spell native returns when the session runs no
    /// spellbook — a synthetic scene with no SPEL index, where inventing an
    /// empty spellbook would read as an actor who has learned nothing.
    public static func needsSpellbook(_ call: PapyrusNativeCall) -> PapyrusNativeResult {
        failure(
            call,
            "\(call.functionName) needs a session with a spellbook runtime"
        )
    }
}
