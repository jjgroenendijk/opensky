// Synthetic PERK records for the perk decoder and store suites. Every layout
// is authored from the cited field spec (docs/formats/perks.md) and contains
// no bytes from the game install (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky

enum PerkFixture {
    /// DATA at record level: trait, level, rank count, playable, hidden.
    static func header(
        isTrait: Bool = false,
        level: UInt8 = 0,
        rankCount: UInt8 = 1,
        isPlayable: Bool = true,
        isHidden: Bool = false
    ) -> Data {
        Data([
            isTrait ? 1 : 0,
            level,
            rankCount,
            isPlayable ? 1 : 0,
            isHidden ? 1 : 0
        ])
    }

    /// The record's field run: identity, optional conditions, DATA, optional
    /// NNAM, then the effect sections in order.
    static func fields(
        editorID: String,
        name: String? = nil,
        description: String? = nil,
        conditions: [Data] = [],
        header: Data? = PerkFixture.header(),
        nextPerk: UInt32? = nil,
        effects: [Data] = []
    ) -> Data {
        var data = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        if let name {
            data += ESMFixture.field("FULL", ESMFixture.zstring(name))
        }
        if let description {
            data += ESMFixture.field("DESC", ESMFixture.zstring(description))
        }
        data += conditions.reduce(Data(), +)
        if let header {
            data += ESMFixture.field("DATA", header)
        }
        if let nextPerk {
            data += ESMFixture.field("NNAM", word(nextPerk))
        }
        return data + effects.reduce(Data(), +)
    }

    /// A quest section: PRKE type 0, DATA of quest link + stage + two junk
    /// bytes, PRKF.
    static func questEffect(
        quest: UInt32,
        stage: UInt16,
        rank: UInt8 = 0,
        priority: UInt8 = 0
    ) -> Data {
        var payload = word(quest)
        payload.appendUInt16(stage)
        payload += Data([0xCD, 0xCD]) // unused, junk in vanilla records
        return prke(type: 0, rank: rank, priority: priority)
            + ESMFixture.field("DATA", payload)
            + prkf()
    }

    /// An ability section: PRKE type 1, DATA of one SPEL link, PRKF.
    static func abilityEffect(
        spell: UInt32,
        rank: UInt8 = 0,
        priority: UInt8 = 0
    ) -> Data {
        prke(type: 1, rank: rank, priority: priority)
            + ESMFixture.field("DATA", word(spell))
            + prkf()
    }

    /// An entry-point section: PRKE type 2, the three-byte DATA, one PRKC plus
    /// its CTDA run per tab, then the function parameters and PRKF.
    static func entryPointEffect(
        entryPoint: UInt8,
        function: UInt8,
        conditionTabCount: UInt8? = nil,
        rank: UInt8 = 0,
        priority: UInt8 = 0,
        tabs: [(runOn: Int8, conditions: [Data])] = [],
        functionType: UInt8? = nil,
        functionData: Data? = nil,
        buttonLabel: String? = nil,
        scriptFlags: (options: UInt16, fragmentIndex: UInt16)? = nil,
        terminated: Bool = true
    ) -> Data {
        var data = prke(type: 2, rank: rank, priority: priority)
        data += ESMFixture.field("DATA", Data([
            entryPoint,
            function,
            conditionTabCount ?? UInt8(tabs.count)
        ]))
        for tab in tabs {
            data += ESMFixture.field("PRKC", Data([UInt8(bitPattern: tab.runOn)]))
            data += tab.conditions.reduce(Data(), +)
        }
        if let functionType {
            data += ESMFixture.field("EPFT", Data([functionType]))
        }
        if let buttonLabel {
            data += ESMFixture.field("EPF2", ESMFixture.zstring(buttonLabel))
        }
        if let scriptFlags {
            var payload = Data()
            payload.appendUInt16(scriptFlags.options)
            payload.appendUInt16(scriptFlags.fragmentIndex)
            data += ESMFixture.field("EPF3", payload)
        }
        if let functionData {
            data += ESMFixture.field("EPFD", functionData)
        }
        return terminated ? data + prkf() : data
    }

    static func prke(type: UInt8, rank: UInt8 = 0, priority: UInt8 = 0) -> Data {
        ESMFixture.field("PRKE", Data([type, rank, priority]))
    }

    static func prkf() -> Data {
        ESMFixture.field("PRKF", Data())
    }

    static func word(_ value: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(value)
        return data
    }

    static func float(_ value: Float) -> Data {
        word(value.bitPattern)
    }

    static func floats(_ values: [Float]) -> Data {
        values.reduce(Data()) { $0 + float($1) }
    }

    /// EPFD for the actor-value functions: the actor value as a *float* holding
    /// the index, then the factor.
    ///
    /// A float rather than an integer because that is what the records carry:
    /// xEdit stores the word as `itU32` and reinterprets it as a `Single` before
    /// rounding (`wbEPFDActorValueToStr`), and UESP spells the payload
    /// "float AV, float FACTOR". `AlchemySkillBoosts` reads back 146, not
    /// 0x43120000.
    static func actorValueMultiplier(actorValue: Int32, factor: Float) -> Data {
        float(Float(actorValue)) + float(factor)
    }

    static func record(formID: UInt32 = 0, fields: Data) throws -> ESMRecord {
        let file = try ESMFile(
            data: ESMFixture.tes4()
                + ESMFixture.topGroup(
                    "PERK",
                    contents: ESMFixture.record("PERK", formID: formID, data: fields)
                )
        )
        guard
            let group = file.topGroups.first,
            let child = try group.children().first,
            case let .record(record) = child
        else {
            throw ESMError.malformed("PERK fixture has no record")
        }
        return record
    }

    /// A plugin holding whole PERK records (and optionally SPEL records), for
    /// the store suites.
    static func plugin(
        masters: [String] = [],
        perks: [Data] = [],
        spells: [Data] = [],
        magicEffects: [Data] = [],
        actorValues: [Data] = []
    ) throws -> ESMFile {
        var data = ESMFixture.tes4(masters: masters)
        if !magicEffects.isEmpty {
            data += ESMFixture.topGroup("MGEF", contents: magicEffects.reduce(Data(), +))
        }
        if !actorValues.isEmpty {
            data += ESMFixture.topGroup("AVIF", contents: actorValues.reduce(Data(), +))
        }
        if !spells.isEmpty {
            data += ESMFixture.topGroup("SPEL", contents: spells.reduce(Data(), +))
        }
        if !perks.isEmpty {
            data += ESMFixture.topGroup("PERK", contents: perks.reduce(Data(), +))
        }
        return try ESMFile(data: data)
    }

    static func perkRecord(formID: UInt32, fields: Data) -> Data {
        ESMFixture.record("PERK", formID: formID, data: fields)
    }

    /// The smallest SPEL a perk can point at: an editor ID, a name and a SPIT
    /// the spell store can read. `halfCostPerk` fills the PERK link at SPIT
    /// offset 0x20, which is the link M19 decoded and left unresolved.
    static func spellRecord(
        formID: UInt32,
        editorID: String,
        name: String,
        halfCostPerk: UInt32 = 0
    ) -> Data {
        var spit = Data(count: 32)
        spit += word(halfCostPerk)
        var fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        fields += ESMFixture.field("FULL", ESMFixture.zstring(name))
        fields += ESMFixture.field("SPIT", spit)
        return ESMFixture.record("SPEL", formID: formID, data: fields)
    }
}
