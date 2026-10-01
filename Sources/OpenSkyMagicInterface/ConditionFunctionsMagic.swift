// Magic condition functions, reading only the `magic` seam. Raw indices from xEdit
// wbDefinitionsTES5.pas: 214 HasMagicEffect, 223 IsSpellTarget, 264 HasSpell, 570
// HasEquippedSpell, 571 GetCurrentCastingType, 572 GetCurrentDeliveryType, 632
// IsCasting, 699 HasMagicEffectKeyword. Only applied effects are stored, so
// `HasMagicEffect` means "affected by", narrower than the wiki's "having".
// See docs/engine/condition-functions.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated extension ConditionFunctions {
    public static func installMagic(_ registry: inout ConditionFunctionRegistry) {
        installSpellKnowledge(&registry)
        installEffectPresence(&registry)
        installCastingState(&registry)
    }

    // MARK: - Knowing a spell, and being its target

    private static func installSpellKnowledge(_ registry: inout ConditionFunctionRegistry) {
        // "Checks to see if this actor has the given Spell or Shout."
        // (<https://ck.uesp.net/wiki/HasSpell_-_Actor>, the Papyrus twin of the
        // condition function) A shout is a SHOU record, which no store here
        // carries, so a parameter naming one is an unavailable record rather
        // than an actor that does not know it.
        registry.register(ConditionFunction(
            index: 264,
            name: "HasSpell",
            parameter1: .formID
        ) { call in
            Self.magicParameter(call, index: 264) { state, spell in
                .success(Self.isTrue(state.knownSpells.contains(spell)))
            }
        })

        // "Returns True if the calling reference is currently being affected by
        // the specified spell, enchantment, ingredient, or potion."
        // (<https://ck.uesp.net/wiki/IsSpellTarget>) Four record types, which
        // is why this compares the *source* of each active effect rather than
        // its MGEF: `ActiveEffectSource.record` already names whichever of the
        // four applied it.
        registry.register(ConditionFunction(
            index: 223,
            name: "IsSpellTarget",
            parameter1: .formID
        ) { call in
            Self.magicParameter(call, index: 223) { state, record in
                .success(Self.isTrue(state.effectSources.contains(record)))
            }
        })
    }

    // MARK: - Carrying an effect

    private static func installEffectPresence(_ registry: inout ConditionFunctionRegistry) {
        // "If the calling reference is being affected by a Spell that can
        // potentially apply the specified Magic Effect, then the condition
        // function returns 1." (<https://ck.uesp.net/wiki/HasMagicEffect>) See
        // the file header for the narrower question OpenSky answers.
        registry.register(ConditionFunction(
            index: 214,
            name: "HasMagicEffect",
            parameter1: .formID
        ) { call in
            Self.magicParameter(call, index: 214) { state, effect in
                .success(Self.isTrue(state.activeEffects.contains(effect)))
            }
        })

        // "If the calling reference is being affected by a Spell that can
        // potentially apply a Magic Effect with the specified Keyword, then the
        // condition function returns 1."
        // (<https://ck.uesp.net/wiki/HasMagicEffectKeyword>)
        registry.register(ConditionFunction(
            index: 699,
            name: "HasMagicEffectKeyword",
            parameter1: .formID
        ) { call in
            Self.magicParameter(call, index: 699) { state, keyword in
                guard
                    let answer = call.context.magic.hasEffectKeyword(keyword, on: state)
                else { return .failure(.unavailableMagic(.record)) }
                return .success(Self.isTrue(answer))
            }
        })
    }

    // MARK: - What a hand is doing

    private static func installCastingState(_ registry: inout ConditionFunctionRegistry) {
        // Whether the casting source holds a spell
        // (<https://ck.uesp.net/wiki/HasEquippedSpell>). The spell parameter is
        // unselectable in the editor, so xEdit types it as a casting source.
        registry.register(ConditionFunction(
            index: 570,
            name: "HasEquippedSpell",
            parameter1: .integer
        ) { call in
            Self.castingSource(call, index: 570) { state, hand in
                .success(Self.isTrue(state.handSpells[hand] != nil))
            }
        })

        // "GetCurrentCastingType or GetCasting will return the Casting Type for
        // the spell currently equipped on the reference actor's Casting Source
        // ... 0 - Constant Effect, 1 - Fire And Forget, 2 - Concentration"
        // (<https://ck.uesp.net/wiki/GetCurrentCastingType>)
        registry.register(ConditionFunction(
            index: 571,
            name: "GetCurrentCastingType",
            parameter1: .integer
        ) { call in
            Self.readiedSpell(call, index: 571) { spell in
                Self.castingTypeValue(of: spell)
            }
        })

        // "0 - Self, 1 - Contact, 2 - Aimed, 3 - Target Actor, 4 - Target Location"
        // (<https://ck.uesp.net/wiki/GetCurrentDeliveryType>). The record calls 1 "Touch".
        registry.register(ConditionFunction(
            index: 572,
            name: "GetCurrentDeliveryType",
            parameter1: .integer
        ) { call in
            Self.readiedSpell(call, index: 572) { spell in
                Self.deliveryValue(of: spell)
            }
        })

        // No Creation Kit page survives for `IsCasting`, so its return is read
        // from the shape the data authors: all twenty vanilla conditions leave
        // both parameter words zero and compare against 0 or 1, which is the
        // no-parameter boolean signature. OpenSky answers it from the cast
        // state machine — charging, ready or concentrating in either hand.
        registry.register(ConditionFunction(
            index: 632,
            name: "IsCasting"
        ) { call in
            Self.magicState(call).map { Self.isTrue($0.isCasting) }
        })
    }

    // MARK: - Shared

    /// The magic state of this condition's run-on reference, or
    /// `.unavailableMagic(.actor)`.
    ///
    /// The two-step is `ConditionCall.actorState()`'s and for the same reason:
    /// "the run-on named nothing" and "the named thing is not an actor this
    /// session tracks magic for" are different gaps.
    public static func magicState(
        _ call: ConditionCall
    ) -> Result<MagicConditionState, ConditionFailure> {
        call.referenceKey().flatMap { key in
            guard let state = call.context.magic.state(of: key) else {
                return .failure(.unavailableMagic(.actor))
            }
            return .success(state)
        }
    }

    /// One function whose parameter #1 is a FormID naming a record: resolve the
    /// parameter to runtime identity, resolve the run-on to magic state, then
    /// let `answer` compare the two.
    public static func magicParameter(
        _ call: ConditionCall,
        index: UInt16,
        answer: (MagicConditionState, ReferenceKey)
            -> Result<Float, ConditionFailure>
    ) -> Result<Float, ConditionFailure> {
        guard let parameter = call.parameter1 else {
            return .failure(.unresolvedParameter(index))
        }
        guard let record = call.context.magic.key(of: parameter.asFormID) else {
            return .failure(.unavailableMagic(.record))
        }
        return magicState(call).flatMap { answer($0, record) }
    }

    /// One function whose parameter #1 is a casting source: resolve it to a
    /// hand, resolve the run-on to magic state, then let `answer` read it.
    public static func castingSource(
        _ call: ConditionCall,
        index: UInt16,
        answer: (MagicConditionState, SpellHand) -> Result<Float, ConditionFailure>
    ) -> Result<Float, ConditionFailure> {
        guard
            let parameter = call.parameter1,
            let source = CastingSource(rawValue: parameter.asInt32)
        else {
            return .failure(.unresolvedParameter(index))
        }
        guard let hand = source.hand else {
            return .failure(.unavailableMagic(.castingSource))
        }
        return magicState(call).flatMap { answer($0, hand) }
    }

    /// One function that reads a SPIT field of the spell readied at parameter
    /// #1's casting source.
    ///
    /// A hand holding nothing is `.unavailableMagic(.equippedSpell)` rather
    /// than a number: every value both functions return names a real casting
    /// type or delivery, so there is none left over to mean "no spell".
    public static func readiedSpell(
        _ call: ConditionCall,
        index: UInt16,
        read: (ResolvedSpell) -> Float?
    ) -> Result<Float, ConditionFailure> {
        castingSource(call, index: index) { state, hand in
            guard let spell = state.handSpells[hand] else {
                return .failure(.unavailableMagic(.equippedSpell))
            }
            guard
                let record = call.context.magic.spells?.spell(key: spell),
                let value = read(record)
            else {
                return .failure(.unavailableMagic(.record))
            }
            return .success(value)
        }
    }

    /// SPIT casting type as the condition function numbers it, or nil for a
    /// value outside the documented three. A scroll's casting type is xEdit's
    /// SCRL-only 3, which `GetCurrentCastingType` does not name.
    public static func castingTypeValue(of spell: ResolvedSpell) -> Float? {
        switch spell.data?.castingType {
        case .constantEffect: 0
        case .fireAndForget: 1
        case .concentration: 2
        case .scroll, .unknown, nil: nil
        }
    }

    /// MGEF delivery as the condition function numbers it, or nil for a
    /// mod-authored value this build has no name for.
    public static func deliveryValue(of spell: ResolvedSpell) -> Float? {
        switch spell.data?.delivery {
        case .selfTarget: 0
        case .touch: 1
        case .aimed: 2
        case .targetActor: 3
        case .targetLocation: 4
        case .unknown, nil: nil
        }
    }
}
