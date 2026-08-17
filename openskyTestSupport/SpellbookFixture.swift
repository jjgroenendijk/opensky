// Synthetic SPEL, EQUP, MGEF and BOOK records for the caster-runtime suites
// (issue #470, roadmap item 19.7). Every byte is authored here; nothing comes
// from the game install (AGENTS.md "Legal & IP boundary").
//
// The spell shapes mirror what the vanilla records actually carry, confirmed
// against the local install through `openskycli record` rather than from
// memory: a self-delivery fire-and-forget heal with a charge time and a
// zero-duration restore entry, a self-delivery concentration heal with no
// charge time and one-second entries, a two-handed master spell, an aimed spell
// (which 19.7 refuses), a greater power and an ability.
//
// Layouts: UESP "Skyrim Mod:Mod File Format" subpages /SPEL, /EQUP, /MGEF and
// /BOOK.

import Foundation
@testable import opensky

@MainActor
enum SpellbookFixture {
    static let pluginName = "Base.esm"

    enum Slot {
        static let rightHand: UInt32 = 0x0100
        static let leftHand: UInt32 = 0x0110
        static let eitherHand: UInt32 = 0x0120
        static let bothHands: UInt32 = 0x0130
        static let voice: UInt32 = 0x0150
    }

    enum Spell {
        /// Fire and forget, self, 0.5 s charge, one instant restore-health
        /// entry. The acceptance picture's spell.
        static let fastHealing: UInt32 = 0x0200
        /// Concentration, self, no charge, one one-second restore entry.
        static let healing: UInt32 = 0x0210
        /// Fire and forget, self, two-handed slot.
        static let masterHeal: UInt32 = 0x0220
        /// Fire and forget, aimed — the delivery 19.8 owns.
        static let firebolt: UInt32 = 0x0230
        /// A greater power, self, once per day.
        static let dragonskin: UInt32 = 0x0240
        /// An ability with one timed entry and one zero-duration entry.
        static let resistFire: UInt32 = 0x0250
        /// Fire and forget, self, named `Flames` so the load-order lookup
        /// `SpellStore.vanillaStartSpellEditorIDs` performs finds it.
        static let flames: UInt32 = 0x0260
        /// Fire and forget, aimed, one hostile fire entry with an area, plus a
        /// point entry — the shape vanilla `Fireball` is authored in
        /// (issue #471).
        static let fireball: UInt32 = 0x0270
        /// Fire and forget, aimed, hostile, with the SPEL "Ignore Resistance"
        /// flag set.
        static let unresistedBolt: UInt32 = 0x0280
        /// Concentration, aimed — the flamethrower shape.
        static let flamestream: UInt32 = 0x0290
        /// Fire and forget, target actor.
        static let sparkAtTarget: UInt32 = 0x02A0
        /// Fire and forget, touch — a delivery 19.8 counts rather than carries
        /// out.
        static let touchOfDeath: UInt32 = 0x02B0
    }

    enum Book {
        /// Teaches `Spell.healing`.
        static let healingTome: UInt32 = 0x0300
        /// Teaches nothing, so reading it marks the book and grants no spell.
        static let novel: UInt32 = 0x0310
    }

    static func key(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: pluginName.lowercased(), objectID: objectID)
    }

    // MARK: - Stores

    static func plugin(extraRecords: [Data] = []) throws -> ESMFile {
        let records = equipSlots + magicEffects + projectiles + spells + books + extraRecords
        let grouped = Dictionary(grouping: records) { record in
            String(bytes: record.prefix(4), encoding: .ascii) ?? "SPEL"
        }
        var data = ESMFixture.tes4()
        for (type, groupedRecords) in grouped.sorted(by: { $0.key < $1.key }) {
            data += ESMFixture.topGroup(type, contents: groupedRecords.reduce(Data(), +))
        }
        return try ESMFile(data: data)
    }

    /// Every fixture record in one index, which is what each store below is
    /// built over. Built once per call rather than cached, so a suite that
    /// mutates nothing shares nothing.
    static func index() throws -> RecordIndex {
        try RecordIndex(
            plugins: [(pluginName, plugin())],
            recordTypes: ["MGEF", "SPEL", "SCRL", "EQUP", "PROJ"]
        )
    }

    /// The MGEF lookup behind every EFID, for a suite that needs a real effect
    /// runtime rather than a fake world (issue #471).
    static func effectStore(index: RecordIndex) -> MagicEffectStore {
        MagicEffectStore(index: index)
    }

    /// The PROJ lookup an aimed cast resolves its projectile through — the
    /// same index the arrow path reads, over the fixture's own records.
    static func projectileStore() throws -> ItemDefinitionStore {
        try ItemDefinitionStore(file: plugin())
    }

    /// A spellbook runtime over a fresh store, plus the store so a suite can
    /// snapshot it.
    static func runtime(
        store: WorldStateStore = WorldStateStore(),
        equipment: EquipmentRuntime? = nil
    ) throws -> (SpellbookRuntime, WorldStateStore) {
        let index = try index()
        return (
            SpellbookRuntime(
                store: store,
                spells: SpellStore(index: index, effects: effectStore(index: index)),
                equipSlots: EquipSlotStore(index: index),
                equipment: equipment
            ),
            store
        )
    }

    /// An actor-value runtime whose subjects all start at 100 of everything and
    /// regenerate nothing, so a magicka number in a suite is only ever what a
    /// cast spent.
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
}
