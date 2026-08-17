// The records `SpellbookFixture` builds its stores over (issues #470 and #471).
//
// Split out of `SpellbookFixture.swift` because the enum reached the strict-lint
// body-length cap once item 19.8 added the aimed, area, unresisted, beam,
// target-actor and touch spells. The seam is the one the file already had: the
// half above answers "what store does a suite get", this half answers "what is
// in it".
//
// Every byte is authored here; nothing comes from the game install (AGENTS.md
// "Legal & IP boundary"). Layouts: UESP "Skyrim Mod:Mod File Format" subpages
// /SPEL, /EQUP, /MGEF, /PROJ and /BOOK.

import Foundation
@testable import opensky

extension SpellbookFixture {
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
    /// Fire Damage: hostile and detrimental, resisted by `Resist Fire`, and
    /// naming a projectile — everything an aimed delivery reads (issue #471).
    static let fireDamage: UInt32 = 0x0012
    /// The PROJ `fireDamage` names.
    static let fireBoltProjectile: UInt32 = 0x0020

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
            ),
            magicEffect(
                formID: fireDamage, editorID: "FireDamage",
                data: effectData(
                    flags: [.hostile, .detrimental],
                    archetype: 0,
                    primaryValue: 24,
                    resistanceValue: ActorValueIndex.resistFire,
                    projectile: fireBoltProjectile
                )
            )
        ]
    }

    /// One PROJ: a flat, fast, short-lived bolt. The numbers are a fixture's,
    /// not a record's — what the suites assert is that the flight model reads
    /// the projectile the MGEF named, not that a particular speed is vanilla's.
    static var projectiles: [Data] {
        [ESMFixture.record(
            "PROJ",
            formID: fireBoltProjectile,
            data: ESMFixture.field("EDID", ESMFixture.zstring("FireboltProjectile"))
                + ESMFixture.field("DATA", projectileData())
        )]
    }

    /// PROJ DATA, flags through range — the shortest payload the decoder
    /// accepts, which is all the flight model needs.
    static func projectileData(
        speed: Float = 3000,
        gravity: Float = 0,
        range: Float = 4000
    ) -> Data {
        var data = Data()
        data.appendUInt16(0)
        data.appendUInt16(0x01) // missile
        data.appendUInt32(gravity.bitPattern)
        data.appendUInt32(speed.bitPattern)
        data.appendUInt32(range.bitPattern)
        return data
    }

    /// One MGEF DATA block. Offsets are UESP's: 0x00 flags, 0x04 base cost,
    /// 0x40 archetype, 0x44 primary actor value. Everything else is zero, which
    /// is a valid record and keeps the fixture honest about what the planner
    /// and the cost formula actually read.
    static func effectData(
        flags: MagicEffectFlags = [],
        baseCost: Float = 1,
        archetype: UInt32 = 0,
        primaryValue: Int32 = 24,
        resistanceValue: Int32 = ActorValueIdentity.noneIndex,
        projectile: UInt32 = 0
    ) -> Data {
        var words = [UInt32](repeating: 0, count: 38)
        words[0] = flags.rawValue
        words[1] = baseCost.bitPattern
        words[4] = UInt32(bitPattern: resistanceValue)
        words[16] = archetype
        words[17] = UInt32(bitPattern: primaryValue)
        words[18] = projectile
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
                effects: [EffectSpec(fireDamage, 50, 0)]
            ),
            spell(
                formID: Spell.fireball, editorID: "Fireball", equipType: Slot.eitherHand,
                spit: spit(type: 0, chargeTime: 0.5, casting: 1, delivery: 2),
                effects: [
                    EffectSpec(fireDamage, 40, 0, area: 15),
                    EffectSpec(fireDamage, 10, 0)
                ]
            ),
            spell(
                formID: Spell.unresistedBolt, editorID: "UnresistedBolt",
                equipType: Slot.eitherHand,
                spit: spit(
                    type: 0, chargeTime: 0, casting: 1, delivery: 2,
                    flags: SpellFlags.ignoreResistance.rawValue
                ),
                effects: [EffectSpec(fireDamage, 50, 0)]
            ),
            spell(
                formID: Spell.flamestream, editorID: "Flamestream", equipType: Slot.eitherHand,
                spit: spit(
                    type: 0, chargeTime: 0, casting: 2, delivery: 2, castDuration: 0.5
                ),
                effects: [EffectSpec(fireDamage, 8, 0)]
            ),
            spell(
                formID: Spell.sparkAtTarget, editorID: "SparkAtTarget",
                equipType: Slot.eitherHand,
                spit: spit(type: 0, chargeTime: 0, casting: 1, delivery: 3, range: 1500),
                effects: [EffectSpec(fireDamage, 12, 0)]
            ),
            spell(
                formID: Spell.touchOfDeath, editorID: "TouchOfDeath",
                equipType: Slot.eitherHand,
                spit: spit(type: 0, chargeTime: 0, casting: 1, delivery: 1),
                effects: [EffectSpec(fireDamage, 30, 0)]
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
        range: Float = 0,
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
        data.appendUInt32(range.bitPattern)
        data.appendUInt32(0)
        return data
    }

    /// One EFID/EFIT entry of a fixture spell. A named type rather than a
    /// tuple because three members is past the strict-lint tuple cap.
    struct EffectSpec {
        let effect: UInt32
        let magnitude: Float
        let duration: UInt32
        /// EFIT area, authored in feet (issue #471). Zero is a point effect.
        let area: UInt32

        init(_ effect: UInt32, _ magnitude: Float, _ duration: UInt32, area: UInt32 = 0) {
            self.effect = effect
            self.magnitude = magnitude
            self.duration = duration
            self.area = area
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
                area: effect.area,
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
