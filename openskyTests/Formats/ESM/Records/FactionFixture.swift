// Synthetic FACT and NPC_ records for the faction decoder, store and template
// suites. Every layout is authored from the cited field spec
// (docs/formats/factions.md) and contains no bytes from the game install
// (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky

enum FactionFixture {
    /// One XNAM: FACT or RACE link, signed modifier, combat reaction.
    static func relation(_ faction: UInt32, modifier: Int32, reaction: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(faction)
        data.appendUInt32(UInt32(bitPattern: modifier))
        data.appendUInt32(reaction)
        return ESMFixture.field("XNAM", data)
    }

    /// CRVA at its full 20-byte length, or truncated to `byteCount` to stand in
    /// for a record written at an older record version.
    static func crimeValues(
        arrest: Bool = true,
        attackOnSight: Bool = false,
        murder: UInt16 = 1000,
        assault: UInt16 = 40,
        trespass: UInt16 = 5,
        pickpocket: UInt16 = 25,
        unknown: UInt16 = 0,
        stealMultiplier: Float = 0.5,
        escape: UInt16 = 100,
        werewolf: UInt16 = 1000,
        byteCount: Int = Faction.CrimeValues.fullByteCount
    ) -> Data {
        var data = Data([arrest ? 1 : 0, attackOnSight ? 1 : 0])
        data.appendUInt16(murder)
        data.appendUInt16(assault)
        data.appendUInt16(trespass)
        data.appendUInt16(pickpocket)
        data.appendUInt16(unknown)
        data.appendUInt32(stealMultiplier.bitPattern)
        data.appendUInt16(escape)
        data.appendUInt16(werewolf)
        return ESMFixture.field("CRVA", data.prefix(byteCount))
    }

    /// VENV, 12 bytes. `radiusHighWord` is the disputed word at offset 6.
    static func vendorValues(
        startHour: UInt16 = 8,
        endHour: UInt16 = 18,
        radius: UInt16 = 1500,
        radiusHighWord: UInt16 = 0,
        onlyBuysStolenItems: Bool = false,
        notSellBuy: Bool = false
    ) -> Data {
        var data = Data()
        data.appendUInt16(startHour)
        data.appendUInt16(endHour)
        data.appendUInt16(radius)
        data.appendUInt16(radiusHighWord)
        data.append(contentsOf: [onlyBuysStolenItems ? 1 : 0, notSellBuy ? 1 : 0])
        data.appendUInt16(0)
        return ESMFixture.field("VENV", data)
    }

    static func vendorLocation(type: Int32, value: UInt32, radius: Int32) -> Data {
        var data = Data()
        data.appendUInt32(UInt32(bitPattern: type))
        data.appendUInt32(value)
        data.appendUInt32(UInt32(bitPattern: radius))
        return ESMFixture.field("PLVD", data)
    }

    /// One RNAM/MNAM/FNAM group, with either title droppable.
    static func rank(_ index: UInt32, male: String? = nil, female: String? = nil) -> Data {
        var data = Data()
        data.appendUInt32(index)
        var out = ESMFixture.field("RNAM", data)
        if let male {
            out += ESMFixture.field("MNAM", ESMFixture.zstring(male))
        }
        if let female {
            out += ESMFixture.field("FNAM", ESMFixture.zstring(female))
        }
        return out
    }

    static func link(_ type: String, _ value: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(value)
        return ESMFixture.field(type, data)
    }

    static func flags(_ value: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(value)
        return ESMFixture.field("DATA", data)
    }

    /// A whole FACT record's bytes: identity first, then whatever the caller
    /// appended, in the order the caller gave.
    static func record(
        formID: UInt32,
        editorID: String?,
        name: String? = nil,
        body: Data = Data()
    ) -> Data {
        var fields = Data()
        if let editorID {
            fields += ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        }
        if let name {
            fields += ESMFixture.field("FULL", ESMFixture.zstring(name))
        }
        return ESMFixture.record("FACT", formID: formID, data: fields + body)
    }

    /// AIDT at its full 20-byte length, or truncated to `byteCount` to stand in
    /// for a record a mod wrote short (docs/formats/actors.md).
    static func aiData(
        aggression: UInt8 = 0,
        confidence: UInt8 = 2,
        energy: UInt8 = 50,
        morality: UInt8 = 0,
        mood: UInt8 = 0,
        assistance: UInt8 = 0,
        aggroRadiusBehavior: Bool = false,
        unknown: UInt8 = 0,
        warn: UInt32 = 0,
        warnOrAttack: UInt32 = 0,
        attack: UInt32 = 0,
        byteCount: Int = ActorAIData.byteCount
    ) -> Data {
        var data = Data([
            aggression, confidence, energy, morality, mood, assistance,
            aggroRadiusBehavior ? 1 : 0, unknown
        ])
        data.appendUInt32(warn)
        data.appendUInt32(warnOrAttack)
        data.appendUInt32(attack)
        return ESMFixture.field("AIDT", data.prefix(byteCount))
    }

    /// An NPC_ carrying the minimum ACBS the decoder requires, a template link
    /// and template flags, a SNAM run and an optional AIDT.
    static func actor(
        formID: UInt32,
        editorID: String,
        templateFlags: UInt16 = 0,
        template: UInt32? = nil,
        factions: [(faction: UInt32, rank: Int8)] = [],
        aiData: Data = Data()
    ) -> Data {
        var acbs = Data()
        acbs.appendUInt32(0) // flags
        for _ in 0 ..< 6 {
            acbs.appendUInt16(0) // magicka ... speed multiplier
        }
        acbs.appendUInt16(0) // disposition base
        acbs.appendUInt16(templateFlags)
        acbs.appendUInt16(0) // health offset
        acbs.appendUInt16(0) // bleedout override
        var fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
            + ESMFixture.field("ACBS", acbs)
        if let template {
            fields += link("TPLT", template)
        }
        for membership in factions {
            var data = Data()
            data.appendUInt32(membership.faction)
            data.append(UInt8(bitPattern: membership.rank))
            data.append(Data(count: 3)) // unused in Skyrim (xEdit wbFaction)
            fields += ESMFixture.field("SNAM", data)
        }
        return ESMFixture.record("NPC_", formID: formID, data: fields + aiData)
    }

    /// Parses one fixture record out of its bytes.
    static func decode(_ bytes: Data) throws -> ESMRecord {
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("fixture did not produce a record")
        }
        return record
    }
}
