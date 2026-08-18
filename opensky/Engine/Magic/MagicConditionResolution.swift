// The one place a condition asks "what magic is on this actor right now?"
// (issue #474, roadmap item 19.11), mirroring `ActorStateResolution` and
// `ConditionDataResolution`.
//
// Shaped as a resolved snapshot rather than as a live handle for the reason
// every other seam on `ConditionContext` is: the evaluator is a nonisolated
// value a build thread may run, so a condition body cannot reach into
// `WorldStateStore`, `SpellbookRuntime`, `ActiveEffectRuntime` or
// `CasterRuntime`. The caller that *is* on the main actor reads all four and
// hands the result over.
//
// ## What one entry carries, and why each field is here
//
// Known spells, because `HasSpell` asks nothing else. The MGEF of every active
// effect, because `HasMagicEffect` compares exactly that. The record each
// active effect came from, because `IsSpellTarget` names the spell, potion or
// enchantment rather than the effect. The spell readied in each hand, because
// the three casting-source functions all start there. And which hands have a
// cast running, because `IsCasting` is about the cast and not about the hand's
// contents.
//
// The two record stores ride along beside the per-actor states because every
// one of these functions takes a FormID parameter that has to be resolved
// against the load order before it can be compared, and two of them read the
// record afterwards: `GetCurrentCastingType` and `GetCurrentDeliveryType` are
// SPIT fields of the readied spell. Held the way `ConditionDataResolution`
// holds its three stores, for the same reason.
//
// Documented in docs/formats/conditions.md and docs/engine/magic.md.

import Foundation

/// One actor's magic as a condition sees it.
nonisolated struct MagicConditionState: Equatable, Sendable {
    /// SPEL and SCRL records this actor knows.
    var knownSpells: Set<ReferenceKey>
    /// The MGEF behind every effect currently acting on this actor.
    var activeEffects: Set<ReferenceKey>
    /// The SPEL, ALCH, INGR or ENCH record each of those effects came from.
    var effectSources: Set<ReferenceKey>
    /// The spell readied in each hand, absent for a hand holding none.
    var handSpells: [SpellHand: ReferenceKey]
    /// Hands with a cast in flight — charging, ready or concentrating.
    var castingHands: Set<SpellHand>

    init(
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

    /// This actor's state built from the three components the runtime stores,
    /// so the app-side builder and a test agree on how a component becomes a
    /// condition fact.
    init(
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

    var isCasting: Bool {
        !castingHands.isEmpty
    }
}

/// Which hand or slot a casting-source parameter names.
///
/// The values are xEdit dev-4.1.6 `wbCastingSourceEnum` in
/// Core/wbDefinitionsTES5.pas: `Left`, `Right`, `Voice`, `Instant`. The
/// Creation Kit wiki's `EquipSpell - Actor` page spells the same numbering for
/// the Papyrus side — "0: Left hand, 1: Right hand, 2: Voice (use this for
/// Powers)" — so one type serves the condition parameter and the native
/// argument.
nonisolated enum CastingSource: Int32, CaseIterable, Sendable {
    case left = 0
    case right = 1
    case voice = 2
    case instant = 3

    /// The hand this source is, or nil for the two slots OpenSky readies
    /// nothing into. A voice slot is where a shout or a greater power sits and
    /// `SpellbookState` has no such slot; an instant source is not an equip
    /// slot at all. Both report the gap rather than answering "nothing
    /// equipped", which is a different fact.
    var hand: SpellHand? {
        switch self {
        case .left: .left
        case .right: .right
        case .voice, .instant: nil
        }
    }
}

/// Every actor's magic state plus the record stores the parameters resolve
/// against.
///
/// `@unchecked Sendable` for the reason `ConditionDataResolution` is: the two
/// stores are immutable value snapshots built once at load, and only their
/// `RecordIndex` back-reference keeps them from being checked automatically.
nonisolated struct MagicConditionResolution: @unchecked Sendable {
    /// Load-order SPEL and SCRL lookup, for the readied spell's SPIT header.
    let spells: SpellStore?
    /// Load-order MGEF lookup, for an effect's keyword list.
    let effects: MagicEffectStore?
    /// The plugin a condition's FormID parameters are spelled against.
    let sourcePlugin: String?

    private let states: [ReferenceKey: MagicConditionState]

    static let empty = MagicConditionResolution()

    init(
        spells: SpellStore? = nil,
        effects: MagicEffectStore? = nil,
        sourcePlugin: String? = nil,
        states: [ReferenceKey: MagicConditionState] = [:]
    ) {
        self.spells = spells
        self.effects = effects
        self.sourcePlugin = sourcePlugin
        self.states = states
    }

    func state(of reference: ReferenceKey) -> MagicConditionState? {
        states[reference]
    }

    /// One FormID parameter as the runtime identity the components store.
    ///
    /// Resolution goes through whichever store the session carries, because
    /// both wrap the same `RecordIndex` master-list machinery and a parameter
    /// may legitimately name a record neither store holds — `IsSpellTarget`
    /// names potions and enchantments as readily as spells.
    func key(of formID: FormID) -> ReferenceKey? {
        guard let sourcePlugin else { return nil }
        if let resolved = spells?.resolvedID(formID, fromPlugin: sourcePlugin) {
            return ReferenceKey(resolved: resolved)
        }
        guard let resolved = effects?.resolvedID(formID, fromPlugin: sourcePlugin) else {
            return nil
        }
        return ReferenceKey(resolved: resolved)
    }

    /// Whether any effect acting on `reference` carries `keyword`.
    ///
    /// Nil when no effect store is wired, which keeps "OpenSky has no MGEF
    /// records" apart from "no effect on this actor carries that keyword".
    func hasEffectKeyword(_ keyword: ReferenceKey, on state: MagicConditionState) -> Bool? {
        guard let effects else { return nil }
        return state.activeEffects.contains { effect in
            guard let record = effects.effect(key: effect) else { return false }
            return record.keywordKeys(in: effects).contains(keyword)
        }
    }
}
