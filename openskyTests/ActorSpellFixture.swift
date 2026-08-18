// Synthetic NPC_, RACE and LVSP records for the spell-baseline suite (issue
// #473, roadmap item 19.10).
//
// Its own file rather than private helpers in the suite, because the records
// here are the smallest ones that carry a `SPLO` run and the suite reads better
// as a list of resolutions than as a list of byte layouts.
//
// Every byte is authored here; nothing comes from the game install (AGENTS.md
// "Legal & IP boundary"). Layouts: UESP "Skyrim Mod:Mod File Format" subpages
// /NPC_, /RACE and /LVSP.

import Foundation
@testable import opensky

enum ActorSpellFixture {
    /// ACBS, 24 bytes: uint32 flags, 7 stat words, uint16 template flags, two
    /// tail words.
    static func acbs(templateFlags: UInt16) -> Data {
        var data = Data()
        data.appendUInt32(0)
        for _ in 0 ..< 7 {
            data.appendUInt16(0)
        }
        data.appendUInt16(templateFlags)
        data.appendUInt16(0)
        data.appendUInt16(0)
        return data
    }

    static func formIDField(_ type: String, _ value: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(value)
        return ESMFixture.field(type, data)
    }

    /// The one record a fixture byte string contains.
    static func record(_ bytes: Data) throws -> ESMRecord {
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("fixture did not produce a record")
        }
        return record
    }

    static func npc(
        formID: UInt32,
        templateFlags: UInt16 = 0,
        template: UInt32? = nil,
        race: UInt32? = nil,
        spells: [UInt32] = []
    ) throws -> ActorBase {
        var fields = ESMFixture.field("ACBS", acbs(templateFlags: templateFlags))
        if let template {
            fields += formIDField("TPLT", template)
        }
        if let race {
            fields += formIDField("RNAM", race)
        }
        // SPCT states how many entries follow; the decoder counts them instead,
        // and the fixture writes it so the record is the shape a plugin holds.
        var count = Data()
        count.appendUInt32(UInt32(spells.count))
        fields += ESMFixture.field("SPCT", count)
        for spell in spells {
            fields += formIDField("SPLO", spell)
        }
        return try ActorBase(
            record: record(ESMFixture.record("NPC_", formID: formID, data: fields)),
            localized: false
        )
    }

    static func race(formID: UInt32, spells: [UInt32]) throws -> Race {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("TestRace"))
        for spell in spells {
            fields += formIDField("SPLO", spell)
        }
        return try Race(
            record: record(ESMFixture.record("RACE", formID: formID, data: fields)),
            localized: false
        )
    }

    static func lvsp(
        formID: UInt32,
        entries: [LeveledList.Entry]
    ) throws -> LeveledList {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("TestLeveledSpell"))
            + ESMFixture.field("LVLD", Data([0]))
            + ESMFixture.field("LVLF", Data([0]))
            + ESMFixture.field("LLCT", Data([UInt8(entries.count)]))
        for entry in entries {
            var data = Data()
            data.appendUInt16(entry.level)
            data.appendUInt16(0)
            data.appendUInt32(entry.reference.rawValue)
            data.appendUInt32(entry.count)
            fields += ESMFixture.field("LVLO", data)
        }
        return try LeveledList(
            record: record(ESMFixture.record("LVSP", formID: formID, data: fields))
        )
    }

    static func resolver(
        npcs: [ActorBase],
        races: [Race] = [],
        leveledSpells: [LeveledList] = []
    ) -> ActorSpellBaselineResolver {
        ActorSpellBaselineResolver(
            templates: ActorTemplateResolver(
                actors: Dictionary(uniqueKeysWithValues: npcs.map { ($0.formID.rawValue, $0) }),
                leveledActors: [:],
                leveledSpells: Dictionary(
                    uniqueKeysWithValues: leveledSpells.map { ($0.formID.rawValue, $0) }
                )
            ),
            races: Dictionary(uniqueKeysWithValues: races.map { ($0.formID.rawValue, $0) })
        )
    }
}
