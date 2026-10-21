// Synthetic MGEF records for the archetype suites, one effect per rule.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsTesting
@testable import OpenSkyGameData

extension ActiveEffectFixture {
    /// The archetype effects of `archetypeRecords`, one per rule.
    public enum Archetype {
        public static let calm: UInt32 = 0x30
        public static let absorbHealth: UInt32 = 0x31
        public static let invisibility: UInt32 = 0x32
        public static let dispel: UInt32 = 0x33
        public static let cureParalysis: UInt32 = 0x34
        public static let turnUndead: UInt32 = 0x35
        public static let script: UInt32 = 0x36
        public static let wardAccumulate: UInt32 = 0x37
        public static let stagger: UInt32 = 0x38
        public static let spawnHazard: UInt32 = 0x39
        public static let cloak: UInt32 = 0x3A
        public static let summon: UInt32 = 0x3B
        public static let frenzy: UInt32 = 0x3C
        public static let demoralize: UInt32 = 0x3D
        public static let rally: UInt32 = 0x3E
        public static let hazard: UInt32 = 0x3F
        public static let cloakSpell: UInt32 = 0x40
        public static let soulTrap: UInt32 = 0x41
        public static let slowTime: UInt32 = 0x42
        public static let reanimate: UInt32 = 0x43
        /// The `NPC_` the summon effect names.
        public static let summonedActor: UInt32 = 0x44
        public static let light: UInt32 = 0x45
        /// `Ward Power` in the vanilla actor-value table.
        public static let wardPower: Int32 = 63
    }

    private struct ArchetypeSpec {
        let formID: UInt32
        let editorID: String
        let flags: MagicEffectFlags
        let archetype: UInt32
        var value: Int32 = -1
        var item: UInt32 = 0
    }

    /// One effect per archetype rule. Raw archetypes are xEdit's `wbArchtypeEnum`.
    public static var archetypeRecords: [Data] {
        let specs = [
            ArchetypeSpec(
                formID: Archetype.calm, editorID: "Calm",
                flags: [.hostile, .detrimental, .recover], archetype: 6
            ),
            ArchetypeSpec(
                formID: Archetype.absorbHealth, editorID: "AbsorbHealth",
                flags: [.hostile, .detrimental], archetype: 4, value: 24
            ),
            ArchetypeSpec(
                formID: Archetype.invisibility, editorID: "Invisibility",
                flags: [.recover], archetype: 11, value: 54
            ),
            ArchetypeSpec(formID: Archetype.dispel, editorID: "Dispel", flags: [], archetype: 2),
            ArchetypeSpec(
                formID: Archetype.cureParalysis, editorID: "CureParalysis", flags: [], archetype: 27
            ),
            ArchetypeSpec(
                formID: Archetype.turnUndead, editorID: "TurnUndead",
                flags: [.hostile, .recover], archetype: 24
            ),
            ArchetypeSpec(
                formID: Archetype.script,
                editorID: "ScriptEffect",
                flags: [],
                archetype: 1
            ),
            ArchetypeSpec(
                formID: Archetype.wardAccumulate, editorID: "Ward",
                flags: [.recover], archetype: 32, value: Archetype.wardPower
            ),
            ArchetypeSpec(formID: Archetype.stagger, editorID: "Stagger", flags: [], archetype: 33),
            ArchetypeSpec(
                formID: Archetype.spawnHazard, editorID: "SpawnHazard",
                flags: [], archetype: 40, item: Archetype.hazard
            ),
            ArchetypeSpec(
                formID: Archetype.cloak, editorID: "Cloak",
                flags: [.recover], archetype: 35, item: Archetype.cloakSpell
            ),
            ArchetypeSpec(
                formID: Archetype.summon, editorID: "Summon", flags: [], archetype: 18,
                item: Archetype.summonedActor
            ),
            ArchetypeSpec(
                formID: Archetype.reanimate, editorID: "Reanimate", flags: [], archetype: 22
            ),
            ArchetypeSpec(formID: Archetype.light, editorID: "Light", flags: [], archetype: 12),
            ArchetypeSpec(
                formID: Archetype.frenzy, editorID: "Frenzy", flags: [.hostile, .recover],
                archetype: 8
            ),
            ArchetypeSpec(
                formID: Archetype.demoralize, editorID: "Demoralize",
                flags: [.hostile, .recover], archetype: 7
            ),
            ArchetypeSpec(
                formID: Archetype.rally,
                editorID: "Rally",
                flags: [.recover],
                archetype: 38
            ),
            ArchetypeSpec(
                formID: Archetype.soulTrap, editorID: "SoulTrap", flags: [.hostile], archetype: 23
            ),
            ArchetypeSpec(
                formID: Archetype.slowTime,
                editorID: "SlowTime",
                flags: [],
                archetype: 37
            )
        ]
        return specs.map { spec in
            magicEffect(
                formID: spec.formID, editorID: spec.editorID, name: spec.editorID,
                data: data(
                    flags: spec.flags, associatedItem: spec.item,
                    archetype: spec.archetype, primaryValue: spec.value
                )
            )
        }
    }
}
