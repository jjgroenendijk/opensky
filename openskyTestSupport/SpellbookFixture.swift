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
        let records = equipSlots + magicEffects + spells + books + extraRecords
        let grouped = Dictionary(grouping: records) { record in
            String(bytes: record.prefix(4), encoding: .ascii) ?? "SPEL"
        }
        var data = ESMFixture.tes4()
        for (type, groupedRecords) in grouped.sorted(by: { $0.key < $1.key }) {
            data += ESMFixture.topGroup(type, contents: groupedRecords.reduce(Data(), +))
        }
        return try ESMFile(data: data)
    }

    /// A spellbook runtime over a fresh store, plus the store so a suite can
    /// snapshot it.
    static func runtime(
        store: WorldStateStore = WorldStateStore(),
        equipment: EquipmentRuntime? = nil
    ) throws -> (SpellbookRuntime, WorldStateStore) {
        let file = try plugin()
        let index = RecordIndex(
            plugins: [(pluginName, file)],
            recordTypes: ["MGEF", "SPEL", "SCRL", "EQUP"]
        )
        return (
            SpellbookRuntime(
                store: store,
                spells: SpellStore(index: index, effects: MagicEffectStore(index: index)),
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

    // MARK: - Records

    static var equipSlots: [Data] {
        [
            EquipSlotFixture.record(formID: Slot.rightHand, editorID: "RightHand"),
            EquipSlotFixture.record(formID: Slot.leftHand, editorID: "LeftHand"),
            EquipSlotFixture.record(
                formID: Slot.eitherHand, editorID: "EitherHand",
                parents: [Slot.leftHand, Slot.rightHand], usesAllParents: false
            ),
            EquipSlotFixture.record(
                formID: Slot.bothHands, editorID: "BothHands",
                parents: [Slot.leftHand, Slot.rightHand], usesAllParents: true
            ),
            EquipSlotFixture.record(formID: Slot.voice, editorID: "Voice")
        ]
    }

    /// Restore Health: value modifier on health, Recover clear, base cost 1.
    static let restoreHealth: UInt32 = 0x0010
    /// Fortify Resist Fire: value modifier on a non-primary value with Recover
    /// set, which is the held-modifier behaviour an ability wants.
    static let fortifyResistFire: UInt32 = 0x0011

    /// The two MGEF records every spell here points at. Both carry base cost 1,
    /// so every spell cost in the suites comes out of the documented formula
    /// with one term rather than from a number nobody can check.
    static var magicEffects: [Data] {
        [
            magicEffect(
                formID: restoreHealth, editorID: "RestoreHealth",
                data: effectData(archetype: 0, primaryValue: 24)
            ),
            magicEffect(
                formID: fortifyResistFire, editorID: "FortifyResistFire",
                data: effectData(
                    flags: [.recover], archetype: 0,
                    primaryValue: ActorValueIndex.resistFire
                )
            )
        ]
    }

    /// One MGEF DATA block. Offsets are UESP's: 0x00 flags, 0x04 base cost,
    /// 0x40 archetype, 0x44 primary actor value. Everything else is zero, which
    /// is a valid record and keeps the fixture honest about what the planner
    /// and the cost formula actually read.
    static func effectData(
        flags: MagicEffectFlags = [],
        baseCost: Float = 1,
        archetype: UInt32 = 0,
        primaryValue: Int32 = 24
    ) -> Data {
        var words = [UInt32](repeating: 0, count: 38)
        words[0] = flags.rawValue
        words[1] = baseCost.bitPattern
        words[16] = archetype
        words[17] = UInt32(bitPattern: primaryValue)
        words[22] = UInt32(bitPattern: Int32(-1))
        var data = Data()
        for word in words {
            data.appendUInt32(word)
        }
        return data
    }

    static func magicEffect(formID: UInt32, editorID: String, data: Data) -> Data {
        ESMFixture.record(
            "MGEF",
            formID: formID,
            data: ESMFixture.field("EDID", ESMFixture.zstring(editorID))
                + ESMFixture.field("FULL", ESMFixture.zstring(editorID))
                + ESMFixture.field("DATA", data)
        )
    }

    static var spells: [Data] {
        [
            spell(
                formID: Spell.fastHealing, editorID: "FastHealing", equipType: Slot.eitherHand,
                spit: spit(type: 0, chargeTime: 0.5, casting: 1, delivery: 0),
                effects: [EffectSpec(restoreHealth, 20, 0)]
            ),
            spell(
                formID: Spell.healing, editorID: "Healing", equipType: Slot.eitherHand,
                spit: spit(type: 0, chargeTime: 0, casting: 2, delivery: 0, castDuration: 0.5),
                effects: [EffectSpec(restoreHealth, 10, 1)]
            ),
            spell(
                formID: Spell.masterHeal, editorID: "MasterHeal", equipType: Slot.bothHands,
                spit: spit(type: 0, chargeTime: 0, casting: 1, delivery: 0),
                effects: [EffectSpec(restoreHealth, 30, 0)]
            ),
            spell(
                formID: Spell.firebolt, editorID: "Firebolt", equipType: Slot.eitherHand,
                spit: spit(type: 0, chargeTime: 0.5, casting: 1, delivery: 2),
                effects: [EffectSpec(restoreHealth, 10, 0)]
            ),
            spell(
                formID: Spell.dragonskin, editorID: "Dragonskin", equipType: Slot.voice,
                spit: spit(type: 2, chargeTime: 0, casting: 1, delivery: 0),
                effects: [EffectSpec(restoreHealth, 5, 0)]
            ),
            spell(
                formID: Spell.resistFire, editorID: "ResistFireAbility", equipType: Slot.voice,
                spit: spit(type: 4, chargeTime: 0, casting: 0, delivery: 0),
                effects: [
                    EffectSpec(fortifyResistFire, 25, 60),
                    EffectSpec(fortifyResistFire, 10, 0)
                ]
            ),
            spell(
                formID: Spell.flames, editorID: "Flames", equipType: Slot.eitherHand,
                spit: spit(type: 0, chargeTime: 0, casting: 1, delivery: 0),
                effects: [EffectSpec(restoreHealth, 5, 0)]
            )
        ]
    }

    static var books: [Data] {
        [
            book(formID: Book.healingTome, editorID: "SpellTomeHealing", teaches: Spell.healing),
            book(formID: Book.novel, editorID: "ANovel", teaches: nil)
        ]
    }

    // MARK: - Builders

    /// SPIT: base cost, flags, type, charge time, casting type, delivery, cast
    /// duration, range, half-cost perk.
    static func spit(
        type: UInt32,
        chargeTime: Float,
        casting: UInt32,
        delivery: UInt32,
        castDuration: Float = 0,
        flags: UInt32 = 0
    ) -> Data {
        var data = Data()
        data.appendUInt32(0)
        data.appendUInt32(flags)
        data.appendUInt32(type)
        data.appendUInt32(chargeTime.bitPattern)
        data.appendUInt32(casting)
        data.appendUInt32(delivery)
        data.appendUInt32(castDuration.bitPattern)
        data.appendUInt32(Float(0).bitPattern)
        data.appendUInt32(0)
        return data
    }

    /// One EFID/EFIT entry of a fixture spell. A named type rather than a
    /// tuple because three members is past the strict-lint tuple cap.
    struct EffectSpec {
        let effect: UInt32
        let magnitude: Float
        let duration: UInt32

        init(_ effect: UInt32, _ magnitude: Float, _ duration: UInt32) {
            self.effect = effect
            self.magnitude = magnitude
            self.duration = duration
        }
    }

    static func spell(
        formID: UInt32,
        editorID: String,
        equipType: UInt32,
        spit: Data,
        effects: [EffectSpec]
    ) -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        fields += ESMFixture.field("FULL", ESMFixture.zstring(editorID))
        fields += InventoryFixture.formIDField("ETYP", equipType)
        fields += ESMFixture.field("SPIT", spit)
        for effect in effects {
            fields += InventoryFixture.effectFields(
                effect: effect.effect,
                magnitude: effect.magnitude,
                area: 0,
                duration: effect.duration
            )
        }
        return ESMFixture.record("SPEL", formID: formID, data: fields)
    }

    /// A BOOK whose DATA carries the "teaches spell" flag when it names one.
    static func book(formID: UInt32, editorID: String, teaches: UInt32?) -> Data {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
            + ESMFixture.field("FULL", ESMFixture.zstring(editorID))
            + ESMFixture.field("DATA", InventoryFixture.bookData(
                flags: teaches == nil ? 0x00 : 0x04,
                kind: 0,
                teaches: teaches ?? 0,
                value: 50,
                weight: 1
            ))
        return ESMFixture.record("BOOK", formID: formID, data: fields)
    }
}
