// Magic state per actor for the magic condition functions. See
// docs/engine/condition-functions.md and docs/engine/spellcasting.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData

/// One actor's magic as a condition sees it.
nonisolated public struct MagicConditionState: Equatable, Sendable {
    /// SPEL and SCRL records this actor knows.
    public var knownSpells: Set<ReferenceKey>
    /// The MGEF behind every effect currently acting on this actor.
    public var activeEffects: Set<ReferenceKey>
    /// The SPEL, ALCH, INGR or ENCH record each of those effects came from.
    public var effectSources: Set<ReferenceKey>
    /// The spell readied in each hand, absent for a hand holding none.
    public var handSpells: [SpellHand: ReferenceKey]
    /// Hands with a cast in flight — charging, ready or concentrating.
    public var castingHands: Set<SpellHand>

    public init(
        knownSpells: Set<ReferenceKey> = [],
        activeEffects: Set<ReferenceKey> = [],
        effectSources: Set<ReferenceKey> = [],
        handSpells: [SpellHand: ReferenceKey] = [:],
        castingHands: Set<SpellHand> = []
    ) {
        self.knownSpells = knownSpells
        self.activeEffects = activeEffects
        self.effectSources = effectSources
        self.handSpells = handSpells
        self.castingHands = castingHands
    }

    /// Built from the runtime components, so the app and a test agree on how
    /// a component becomes a condition fact.
    public init(
        spellbook: SpellbookState,
        effects: ActiveEffectState,
        castingHands: Set<SpellHand> = []
    ) {
        self.init(
            knownSpells: Set(spellbook.known),
            activeEffects: Set(effects.effects.map(\.effect)),
            effectSources: Set(effects.effects.map(\.source.record)),
            handSpells: SpellHand.allCases.reduce(into: [:]) { table, hand in
                table[hand] = spellbook.spell(in: hand)
            },
            castingHands: castingHands
        )
    }

    public var isCasting: Bool {
        !castingHands.isEmpty
    }
}

/// Which hand or slot a casting-source parameter or Papyrus argument names.
/// Values from xEdit `wbCastingSourceEnum` (Core/wbDefinitionsTES5.pas).
nonisolated public enum CastingSource: Int32, CaseIterable, Sendable {
    case left = 0
    case right = 1
    case voice = 2
    case instant = 3

    /// Nil for voice and instant: `SpellbookState` has no such slot, and a gap
    /// is a different answer from "nothing equipped".
    public var hand: SpellHand? {
        switch self {
        case .left: .left
        case .right: .right
        case .voice, .instant: nil
        }
    }
}

/// Every actor's magic state plus the SPEL and MGEF stores the parameters
/// resolve against.
nonisolated public struct MagicConditionResolution: Sendable {
    public let facts: ActorConditionFacts<SpellStore, MagicConditionState>
    /// Load-order MGEF lookup, for an effect's keyword list.
    public let effects: MagicEffectStore?

    public static let empty = MagicConditionResolution()

    public init(
        spells: SpellStore? = nil,
        effects: MagicEffectStore? = nil,
        sourcePlugin: String? = nil,
        states: [ReferenceKey: MagicConditionState] = [:]
    ) {
        facts = ActorConditionFacts(store: spells, sourcePlugin: sourcePlugin, facts: states)
        self.effects = effects
    }

    /// Load-order SPEL and SCRL lookup, for the readied spell's SPIT header.
    public var spells: SpellStore? {
        facts.store
    }

    public func state(of reference: ReferenceKey) -> MagicConditionState? {
        facts.fact(of: reference)
    }

    /// The record need not exist in either store: `IsSpellTarget` names
    /// potions and enchantments as readily as spells.
    public func key(of formID: FormID) -> ReferenceKey? {
        if let key = facts.resolvedKey(of: formID) {
            return key
        }
        guard
            let sourcePlugin = facts.sourcePlugin,
            let resolved = effects?.resolvedID(formID, fromPlugin: sourcePlugin)
        else { return nil }
        return ReferenceKey(resolved: resolved)
    }

    /// Nil when no effect store is wired, which keeps "no MGEF records" apart
    /// from "no effect on this actor carries that keyword".
    public func hasEffectKeyword(_ keyword: ReferenceKey, on state: MagicConditionState) -> Bool? {
        guard let effects else { return nil }
        return state.activeEffects.contains { effect in
            guard let record = effects.effect(key: effect) else { return false }
            return record.keywordKeys(in: effects).contains(keyword)
        }
    }
}

nonisolated extension MagicConditionResolution: ConditionResolution {}

nonisolated extension ConditionContext {
    /// Empty when no magic runtime is wired, so every magic function is a
    /// reason-tagged false rather than an actor who has learned nothing.
    public var magic: MagicConditionResolution {
        get { self[resolution: MagicConditionResolution.self] }
        set { self[resolution: MagicConditionResolution.self] = newValue }
    }
}
