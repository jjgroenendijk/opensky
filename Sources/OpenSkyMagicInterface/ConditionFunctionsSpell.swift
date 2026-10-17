// Spell-property condition functions, indices from xEdit wbDefinitionsTES5.pas: 39
// GetDisease, 500 EPAlchemyGetMakingPoison, 501 EPAlchemyEffectHasKeyword, 596
// SpellHasKeyword, 602 IsWardState, 627 IsDualCasting, 693 EPMagic_SpellHasKeyword,
// 696 EPMagic_SpellHasSkill, 713 SpellHasCastingPerk, 721 IsPoison, 724
// EffectWasDualCast. See docs/engine/condition-functions-world.md#spells.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData

/// The spell a perk entry point is evaluated for, such as `Mod Spell Cost`.
nonisolated public struct SpellEvaluationResolution: ConditionResolution, Sendable {
    public static let empty = SpellEvaluationResolution(spell: nil)

    public let spell: ResolvedSpell?

    public init(spell: ResolvedSpell?) {
        self.spell = spell
    }
}

/// The potion or poison being made at an alchemy station, and the effect in question.
nonisolated public struct AlchemyConditionResolution: ConditionResolution, Sendable {
    public static let empty = AlchemyConditionResolution(isPoison: nil, effect: nil)

    /// Nil outside an alchemy evaluation.
    public let isPoison: Bool?
    public let effect: ResolvedMagicEffect?

    public init(isPoison: Bool?, effect: ResolvedMagicEffect?) {
        self.isPoison = isPoison
        self.effect = effect
    }
}

nonisolated extension ConditionContext {
    public var spellEvaluation: SpellEvaluationResolution {
        get { self[resolution: SpellEvaluationResolution.self] }
        set { self[resolution: SpellEvaluationResolution.self] = newValue }
    }

    public var alchemy: AlchemyConditionResolution {
        get { self[resolution: AlchemyConditionResolution.self] }
        set { self[resolution: AlchemyConditionResolution.self] = newValue }
    }
}

nonisolated extension ResolvedSpell {
    /// The costliest effect's magic skill, which is the spell's school.
    public var magicSkill: Int32? {
        effects.max { $0.cost < $1.cost }?.effect?.effect.data?.magicSkill
    }

    /// The costliest effect's minimum skill, which sets the spell's level.
    public var minimumSkillLevel: UInt32? {
        effects.max { $0.cost < $1.cost }?.effect?.effect.data?.minimumSkillLevel
    }

    public func hasEffectKeyword(_ keyword: ReferenceKey, in store: MagicEffectStore) -> Bool {
        effects.contains { $0.effect?.keywordKeys(in: store).contains(keyword) == true }
    }
}

nonisolated extension ConditionFunctions {
    static func installSpellProperties(_ registry: inout ConditionFunctionRegistry) {
        registry.register(ConditionFunction(
            index: 596, name: "SpellHasKeyword", parameter1: .integer, parameter2: .formID
        ) { call in
            castingSource(call, index: 596) { state, hand in
                guard let spellKey = state.handSpells[hand] else { return .success(0) }
                return spellKeyword(call, spell: call.context.magic.spells?.spell(key: spellKey))
            }
        })
        registry.register(ConditionFunction(
            index: 693, name: "EPMagic_SpellHasKeyword", parameter1: .formID
        ) { call in
            evaluatedSpell(call) { spell in
                spellKeyword(call, spell: spell, parameter: call.parameter1)
            }
        })
        registry.register(ConditionFunction(
            index: 696, name: "EPMagic_SpellHasSkill", parameter1: .integer
        ) { call in
            evaluatedSpell(call) { spell in
                .success(Self
                    .isTrue(call.parameter1.map { spell.magicSkill == $0.asInt32 } ?? false))
            }
        })
        registry.register(ConditionFunction(
            index: 713, name: "SpellHasCastingPerk", parameter1: .formID
        ) { call in
            guard let perk = call.parameter1.flatMap({ call.context.magic.key(of: $0.asFormID) })
            else {
                return .failure(.unavailableMagic(.record))
            }
            return evaluatedSpell(call) { spell in
                let own = spell.data?.halfCostPerk.flatMap { link in
                    call.context.magic.spells?.resolvedID(link, fromPlugin: spell.sourcePlugin)
                }
                return .success(Self.isTrue(own.map(ReferenceKey.init(resolved:)) == perk))
            }
        })
        registry.register(ConditionFunction(index: 39, name: "GetDisease") { call in
            magicState(call).map { state in
                let spells = call.context.magic.spells
                return Self
                    .isTrue(state.knownSpells
                        .contains { spells?.spell(key: $0)?.spellType == .disease })
            }
        })
        installUnreachedMagic(&registry)
    }

    /// OpenSky casts with one hand at a time and has no ward state, so these read
    /// the run-on's magic and answer the single-hand, no-ward value.
    private static func installUnreachedMagic(_ registry: inout ConditionFunctionRegistry) {
        for (index, name) in [(UInt16(627), "IsDualCasting"), (724, "EffectWasDualCast")] {
            registry.register(ConditionFunction(index: index, name: name) { call in
                magicState(call).map { _ in 0 }
            })
        }
        // Ward state 0 is "none".
        registry
            .register(ConditionFunction(
                index: 602,
                name: "IsWardState",
                parameter1: .integer
            ) { call in
                magicState(call).map { _ in Self.isTrue(call.parameter1?.asInt32 == 0) }
            })
        for (index, name) in [(UInt16(500), "EPAlchemyGetMakingPoison"), (721, "IsPoison")] {
            registry.register(ConditionFunction(index: index, name: name) { call in
                guard let isPoison = call.context.alchemy.isPoison else {
                    return .failure(.unavailableData(.alchemy))
                }
                return .success(Self.isTrue(isPoison))
            })
        }
        registry.register(ConditionFunction(
            index: 501, name: "EPAlchemyEffectHasKeyword", parameter1: .formID
        ) { call in
            guard
                let effect = call.context.alchemy.effect,
                let store = call.context.magic.effects,
                let keyword = call.parameter1.flatMap({ call.context.magic.key(of: $0.asFormID) })
            else { return .failure(.unavailableData(.alchemy)) }
            return .success(Self.isTrue(effect.keywordKeys(in: store).contains(keyword)))
        })
    }

    private static func evaluatedSpell(
        _ call: ConditionCall,
        read: (ResolvedSpell) -> Result<Float, ConditionFailure>
    ) -> Result<Float, ConditionFailure> {
        guard let spell = call.context.spellEvaluation.spell else {
            return .failure(.unavailableMagic(.equippedSpell))
        }
        return read(spell)
    }

    /// Whether any effect of `spell` carries the keyword parameter.
    private static func spellKeyword(
        _ call: ConditionCall,
        spell: ResolvedSpell?,
        parameter: Condition.Parameter? = nil
    ) -> Result<Float, ConditionFailure> {
        guard
            let spell,
            let store = call.context.magic.effects,
            let keyword = (parameter ?? call.parameter2)
                .flatMap({ call.context.magic.key(of: $0.asFormID) })
        else { return .failure(.unavailableMagic(.record)) }
        return .success(Self.isTrue(spell.hasEffectKeyword(keyword, in: store)))
    }
}
