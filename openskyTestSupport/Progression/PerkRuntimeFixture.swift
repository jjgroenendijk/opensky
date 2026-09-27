// The perk world a runtime suite runs in (issue #497, roadmap item 20.4):
// a small load order of PERK, SPEL and MGEF records shaped like the vanilla
// ones the seams read, plus the runtimes over it.
//
// Every byte is authored here; nothing comes from the game install (AGENTS.md
// "Legal & IP boundary"). The perks are modelled on what the install actually
// carries — a two-rank damage chain whose first rank switches itself off with
// `HasPerk <next rank> == 0` and gates on a weapon tab, a blocking perk, a
// spell-cost perk and an ability perk — so a suite asserts against the shape
// the real records have rather than against a shape invented to be easy.

import Foundation
@testable import opensky

@MainActor
enum PerkRuntimeFixture {
    static let pluginName = "PerkRuntime.esm"

    /// PERK identities.
    enum Perk {
        static let damageRank1: UInt32 = 0x0100
        static let damageRank2: UInt32 = 0x0101
        static let blocking: UInt32 = 0x0102
        static let halfCost: UInt32 = 0x0103
        static let spellCost: UInt32 = 0x0104
        static let ability: UInt32 = 0x0105
        static let actorValueDamage: UInt32 = 0x0106
        /// A tree box gated on a skill requirement, shaped like `Armsman20`'s
        /// `GetBaseActorValue One-Handed >= 50` (issue #499).
        static let skillGated: UInt32 = 0x0107
    }

    /// AVIF identities. One record, carrying the One-Handed perk tree the
    /// spend suites climb.
    enum ActorValueInformation {
        static let oneHanded: UInt32 = 0x0300
    }

    /// The One-Handed actor-value index, which the fixture AVIF record claims
    /// by editor ID so a skill requirement stated against it resolves.
    static let oneHandedIndex = ActorValueIdentity.firstSkillIndex

    /// SPEL identities.
    enum Spell {
        /// A manual-cost spell whose SPIT names `Perk.halfCost`.
        ///
        /// Numbered clear of `SpellbookFixture`'s MGEF ids, which this fixture
        /// reuses: two records of different types may not share an object id in
        /// one plugin, and a collision reads as a record that does not resolve.
        static let flames: UInt32 = 0x0210
        /// The ability `Perk.ability` grants: one timed fortify entry.
        static let stoneskin: UInt32 = 0x0211
        /// A spell whose SPIT names the perk that *also* hooks `Mod Spell Cost`,
        /// which is the shape every vanilla school perk has.
        static let selfHalving: UInt32 = 0x0212
    }

    /// The keyword the damage chain's weapon tab asks for. No KYWD record is
    /// authored behind it: the tab exists to be *unbindable*, which is the
    /// documented gap the runtime counts.
    static let weaponKeyword: UInt32 = 0x0030

    /// Entry points the fixture hooks, by their documented ids.
    static let attackDamage = PerkEntryPoint(rawValue: 35)
    static let percentBlocked = PerkEntryPoint(rawValue: 39)
    static let spellCost = PerkEntryPoint(rawValue: 38)

    static func key(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: pluginName.lowercased(), objectID: objectID)
    }

    // MARK: - Stores

    static func index() throws -> RecordIndex {
        try RecordIndex(
            plugins: [(pluginName, plugin())],
            recordTypes: ["MGEF", "SPEL", "SCRL", "PERK", "AVIF"]
        )
    }

    static func informationStore(index: RecordIndex) -> ActorValueInformationStore {
        ActorValueInformationStore(index: index)
    }

    /// Where each fixture perk sits in the fixture tree (issue #499).
    static func trees(index: RecordIndex) -> PerkTreeIndex {
        PerkTreeIndex(
            information: informationStore(index: index),
            perks: perkStore(index: index)
        )
    }

    static func spellStore(index: RecordIndex) -> SpellStore {
        SpellStore(index: index, effects: MagicEffectStore(index: index))
    }

    static func perkStore(index: RecordIndex) -> PerkStore {
        PerkStore(index: index, spells: spellStore(index: index))
    }

    /// A perk runtime over a fresh world-state store, plus the store so a suite
    /// can snapshot it.
    ///
    /// The store argument is optional rather than defaulted because a
    /// main-actor default value cannot be written in a nonisolated context.
    static func runtime(
        store: WorldStateStore? = nil
    ) throws -> (PerkRuntime, WorldStateStore) {
        let worldState = store ?? WorldStateStore()
        return try (
            PerkRuntime(store: worldState, perks: perkStore(index: index())),
            worldState
        )
    }

    /// An actor-value runtime whose subjects start at 100 of everything and
    /// regenerate nothing, matching `SpellbookFixture.values`.
    static func values(store: WorldStateStore) -> ActorValueRuntime {
        ActorValueRuntime(
            store: store,
            baselines: ActorValueBaselineResolver(
                fallback: ActorValueBaseline(
                    maximums: ActorValues(repeating: 100),
                    regenPercentPerSecond: .zero
                )
            )
        )
    }

    // MARK: - Records

    static func plugin() throws -> ESMFile {
        try PerkFixture.plugin(
            perks: perkRecords,
            spells: spellRecords,
            magicEffects: [SpellbookFixture.magicEffect(
                formID: SpellbookFixture.fortifyResistFire,
                editorID: "FortifyResistFire",
                data: SpellbookFixture.effectData(
                    flags: [.recover],
                    archetype: 0,
                    primaryValue: ActorValueIndex.resistFire
                )
            )],
            actorValues: [actorValueInformationRecord]
        )
    }

    static var spellRecords: [Data] {
        [
            spellRecord(
                formID: Spell.flames,
                editorID: "Flames",
                baseCost: 20,
                halfCostPerk: Perk.halfCost
            ),
            spellRecord(
                formID: Spell.selfHalving,
                editorID: "SelfHalving",
                baseCost: 20,
                halfCostPerk: Perk.spellCost
            ),
            spellRecord(
                formID: Spell.stoneskin,
                editorID: "Stoneskin",
                baseCost: 0,
                effects: [EffectSpec(
                    effect: SpellbookFixture.fortifyResistFire, magnitude: 25, duration: 60
                )]
            )
        ]
    }

    static var perkRecords: [Data] {
        [
            PerkFixture.perkRecord(
                formID: Perk.damageRank1,
                fields: PerkFixture.fields(
                    editorID: "DamageRank1",
                    name: "Damage Rank 1",
                    nextPerk: Perk.damageRank2,
                    effects: [PerkFixture.entryPointEffect(
                        entryPoint: attackDamage.rawValue,
                        function: 3, // multiply value
                        tabs: [
                            // Tab 0 is the perk owner: the rank chain's own
                            // switch, exactly as `Armsman00` authors it.
                            (runOn: 0, conditions: [DialogueFixture.condition(
                                functionIndex: 448,
                                comparisonValue: 0,
                                parameter1: Perk.damageRank2
                            )]),
                            // Tab 1 is the weapon, which nothing in this engine
                            // can bind to a world reference.
                            (runOn: 1, conditions: [DialogueFixture.condition(
                                functionIndex: 560,
                                comparisonValue: 1,
                                parameter1: weaponKeyword
                            )])
                        ],
                        functionType: 1,
                        functionData: PerkFixture.float(1.2)
                    )]
                )
            ),
            PerkFixture.perkRecord(
                formID: Perk.damageRank2,
                fields: PerkFixture.fields(
                    editorID: "DamageRank2",
                    name: "Damage Rank 2",
                    effects: [PerkFixture.entryPointEffect(
                        entryPoint: attackDamage.rawValue,
                        function: 3,
                        tabs: [(runOn: 0, conditions: [])],
                        functionType: 1,
                        functionData: PerkFixture.float(1.5)
                    )]
                )
            ),
            PerkFixture.perkRecord(
                formID: Perk.blocking,
                fields: PerkFixture.fields(
                    editorID: "ShieldWall",
                    name: "Shield Wall",
                    effects: [PerkFixture.entryPointEffect(
                        entryPoint: percentBlocked.rawValue,
                        function: 3,
                        tabs: [(runOn: 0, conditions: [])],
                        functionType: 1,
                        functionData: PerkFixture.float(1.25)
                    )]
                )
            ),
            PerkFixture.perkRecord(
                formID: Perk.halfCost,
                fields: PerkFixture.fields(editorID: "HalfCost", name: "Apprentice School")
            ),
            PerkFixture.perkRecord(
                formID: Perk.spellCost,
                fields: PerkFixture.fields(
                    editorID: "CheaperSpells",
                    name: "Cheaper Spells",
                    effects: [PerkFixture.entryPointEffect(
                        entryPoint: spellCost.rawValue,
                        function: 3,
                        tabs: [(runOn: 0, conditions: [])],
                        functionType: 1,
                        functionData: PerkFixture.float(0.8)
                    )]
                )
            ),
            PerkFixture.perkRecord(
                formID: Perk.ability,
                fields: PerkFixture.fields(
                    editorID: "AbilityPerk",
                    name: "Stoneskin",
                    effects: [PerkFixture.abilityEffect(spell: Spell.stoneskin)]
                )
            ),
            PerkFixture.perkRecord(
                formID: Perk.actorValueDamage,
                fields: PerkFixture.fields(
                    editorID: "ActorValueDamage",
                    name: "Skill Scaled Damage",
                    effects: [PerkFixture.entryPointEffect(
                        entryPoint: attackDamage.rawValue,
                        function: 14, // multiply 1 + actor value mult
                        tabs: [(runOn: 0, conditions: [])],
                        functionType: 2,
                        functionData: PerkFixture.actorValueMultiplier(
                            actorValue: ActorValueIndex.resistFire, factor: 0.01
                        )
                    )]
                )
            ),
            PerkFixture.perkRecord(
                formID: Perk.skillGated,
                fields: PerkFixture.fields(
                    editorID: "SkillGated",
                    name: "Skill Gated",
                    // `GetBaseActorValue One-Handed >= 50` on the perk owner,
                    // which is the shape every vanilla rank requirement takes.
                    conditions: [DialogueFixture.condition(
                        functionIndex: 277,
                        operatorBits: 3,
                        comparisonValue: 50,
                        parameter1: UInt32(bitPattern: oneHandedIndex)
                    )]
                )
            )
        ]
    }
}
