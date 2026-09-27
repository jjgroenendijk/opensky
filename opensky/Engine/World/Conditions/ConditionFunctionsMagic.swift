// Magic condition functions (issue #474, roadmap item 19.11), split out of
// `ConditionFunctions` the way the actor and M18 data families are.
//
// Every function here reads the `magic` seam and nothing else, so each answers
// without a world, a clock or a store behind it — which is what lets the whole
// family be driven from a literal in a test.
//
// Indices below are the raw stored numbers; the Creation Kit spells each 4096
// higher. They come from xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas, whose
// condition-function table lists:
//
//   (Index: 214; Name: 'HasMagicEffect'; ParamType1: ptMagicEffect)
//   (Index: 223; Name: 'IsSpellTarget'; ParamType1: ptEffectItem)
//   (Index: 264; Name: 'HasSpell'; ParamType1: ptEffectItem)
//   (Index: 570; Name: 'HasEquippedSpell'; ParamType1: ptCastingSource)
//   (Index: 571; Name: 'GetCurrentCastingType'; ParamType1: ptCastingSource)
//   (Index: 572; Name: 'GetCurrentDeliveryType'; ParamType1: ptCastingSource)
//   (Index: 632; Name: 'IsCasting')
//   (Index: 699; Name: 'HasMagicEffectKeyword'; ParamType1: ptKeyword)
//
// The eight were chosen by measuring the active load order rather than by
// taste; the per-function counts are in docs/formats/conditions.md.
//
// ## The one place OpenSky answers a narrower question than the engine did
//
// The Creation Kit wiki states that `HasMagicEffect` and
// `HasMagicEffectKeyword` are about *carrying* an effect rather than being
// affected by it: "a magic effect will cause this function to return 1 if the
// effect-side conditions are met, even if the spell-side conditions aren't met
// and the effect isn't actually active. In other words, 'having a magic effect'
// is distinct from 'being affected by a magic effect', and this function tests
// for the former." (<https://ck.uesp.net/wiki/HasMagicEffect>) OpenSky stores
// only effects that were actually applied, so it answers the *latter*: an
// effect whose spell-side condition failed was never applied and is invisible
// here. The difference is recorded in docs/formats/conditions.md rather than
// papered over; every effect that is running answers identically.

import Foundation

nonisolated extension ConditionFunctions {
    static func installMagic(_ registry: inout ConditionFunctionRegistry) {
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
        // "HasEquippedSpell or HasSpell will indicate whether or not the
        // reference actor has a spell equipped at a particular Casting Source."
        // (<https://ck.uesp.net/wiki/HasEquippedSpell>) The same page records
        // that the spell parameter is unreachable in the editor —
        // "HasEquippedSpell is currently broken as a condition function. There
        // is no selectable parameter for the Spell ID" — which is why xEdit
        // types the one parameter as a casting source and this asks only
        // whether the source holds anything.
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

        // "GetCurrentDeliveryType or GetDelivery will return the DeliveryType
        // for the spell currently equipped on the reference actor's Casting
        // Source ... 0 - Self, 1 - Contact, 2 - Aimed, 3 - Target Actor,
        // 4 - Target Location"
        // (<https://ck.uesp.net/wiki/GetCurrentDeliveryType>) The record's own
        // vocabulary names 1 "Touch"; the wiki page's "Contact" is the same
        // value.
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
    static func magicState(
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
    static func magicParameter(
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
    static func castingSource(
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
    static func readiedSpell(
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
    static func castingTypeValue(of spell: ResolvedSpell) -> Float? {
        switch spell.data?.castingType {
        case .constantEffect: 0
        case .fireAndForget: 1
        case .concentration: 2
        case .scroll, .unknown, nil: nil
        }
    }

    /// MGEF delivery as the condition function numbers it, or nil for a
    /// mod-authored value this build has no name for.
    static func deliveryValue(of spell: ResolvedSpell) -> Float? {
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
