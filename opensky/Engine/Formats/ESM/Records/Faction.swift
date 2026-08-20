// FACT factions: interfaction relations, the crime-response block a hold's
// guards answer to, rank titles, and the vendor block a merchant's shop hangs
// off. The engine types here are links and raw values only — resolving them
// into hostility, crime response or trade is milestone M21's later issues.
//
// Every variable-size struct is decoded from the payload length rather than a
// record version, so a plugin that writes an older or longer CRVA loses the
// fields it does not carry instead of failing the record.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/FACT":
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/FACT
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas `wbRecord(FACT, ...)`
//   and Core/wbDefinitionsCommon.pas `wbFactionRelations`, `wbPLVD`.
// Layout documented in docs/formats/factions.md.

import Foundation

nonisolated struct FactionDecodeTally: Equatable {
    private(set) var malformedFields: [FourCC: Int] = [:]
    private(set) var unknownFields: [FourCC: Int] = [:]
    /// Bytes past the last whole element of a packed array, or past the last
    /// documented member of a struct that arrived longer than the spec.
    private(set) var trailingBytes: [FourCC: Int] = [:]
    /// VENV offset 6, which xEdit calls "Unknown 1" and UESP folds into a
    /// 32-bit radius. Counted whenever it is nonzero, because a nonzero word
    /// there is the only observation that could tell the two readings apart.
    private(set) var vendorRadiusHighWordSet = 0

    var total: Int {
        malformedFields.values.reduce(0, +)
            + unknownFields.values.reduce(0, +)
            + trailingBytes.values.reduce(0, +)
    }

    mutating func noteMalformed(_ type: FourCC) {
        malformedFields[type, default: 0] += 1
    }

    mutating func noteUnknown(_ type: FourCC) {
        unknownFields[type, default: 0] += 1
    }

    mutating func noteTail(_ type: FourCC, bytes: Int) {
        guard bytes > 0 else { return }
        trailingBytes[type, default: 0] += bytes
    }

    mutating func noteVendorRadiusHighWord() {
        vendorRadiusHighWordSet += 1
    }
}

nonisolated struct Faction: Equatable {
    /// DATA. Bit names follow xEdit, which spells out which crime each "ignore"
    /// bit covers; UESP names the same bits with the same values.
    struct Flags: OptionSet, Equatable {
        let rawValue: UInt32

        static let hiddenFromNPC = Flags(rawValue: 0x0000_0001)
        static let specialCombat = Flags(rawValue: 0x0000_0002)
        static let trackCrime = Flags(rawValue: 0x0000_0040)
        static let ignoreMurder = Flags(rawValue: 0x0000_0080)
        static let ignoreAssault = Flags(rawValue: 0x0000_0100)
        static let ignoreStealing = Flags(rawValue: 0x0000_0200)
        static let ignoreTrespass = Flags(rawValue: 0x0000_0400)
        static let doNotReportCrimesAgainstMembers = Flags(rawValue: 0x0000_0800)
        static let crimeGoldUseDefaults = Flags(rawValue: 0x0000_1000)
        static let ignorePickpocket = Flags(rawValue: 0x0000_2000)
        static let vendor = Flags(rawValue: 0x0000_4000)
        static let canBeOwner = Flags(rawValue: 0x0000_8000)
        static let ignoreWerewolf = Flags(rawValue: 0x0001_0000)
    }

    /// XNAM's third word: how members of the two factions treat each other.
    enum CombatReaction: Equatable, CustomStringConvertible {
        case neutral
        case enemy
        case ally
        case friend
        case unknown(raw: UInt32)

        init(rawValue: UInt32) {
            switch rawValue {
            case 0: self = .neutral
            case 1: self = .enemy
            case 2: self = .ally
            case 3: self = .friend
            default: self = .unknown(raw: rawValue)
            }
        }

        var description: String {
            switch self {
            case .neutral: "neutral"
            case .enemy: "enemy"
            case .ally: "ally"
            case .friend: "friend"
            case let .unknown(raw): "unknown (\(raw))"
            }
        }
    }

    /// One XNAM, 12 bytes. The target is a FACT or a RACE — xEdit accepts both
    /// and vanilla authors both — so nothing here assumes the record type.
    struct Relation: Equatable {
        static let byteCount = 12

        let faction: FormID
        /// Signed disposition modifier. xEdit notes the Creation Kit no longer
        /// edits it and vanilla leaves it zero except on one record.
        let modifier: Int32
        let reaction: CombatReaction
    }

    /// CRVA, 12, 16 or 20 bytes. The three trailing fields arrived in later
    /// record versions, so they are optional rather than defaulted: a caller
    /// that needs the steal multiplier has to decide what an absent one means
    /// (issue #504), and a zero would silently answer for it.
    struct CrimeValues: Equatable {
        static let requiredByteCount = 12
        static let withStealMultiplierByteCount = 16
        static let fullByteCount = 20

        let arrest: Bool
        let attackOnSight: Bool
        let murder: UInt16
        let assault: UInt16
        let trespass: UInt16
        let pickpocket: UInt16
        /// Offset 10. Both sources call it unused and observe nonzero values,
        /// so it is kept verbatim and never read as a gold amount.
        let unknown: UInt16
        let stealMultiplier: Float?
        let escape: UInt16?
        let werewolf: UInt16?
    }

    /// One RNAM/MNAM/FNAM group. The titles are localizable, so they are
    /// `LString` and may be string-table IDs rather than text.
    struct Rank: Equatable {
        let index: UInt32
        var maleTitle: LString?
        var femaleTitle: LString?
    }

    /// VENV, 12 bytes. The two sources disagree about offsets 4...7: xEdit
    /// reads a 16-bit radius followed by two unknown bytes, UESP a 32-bit
    /// radius. This decode follows xEdit and tallies a nonzero word at offset 6
    /// (`FactionDecodeTally.vendorRadiusHighWordSet`), which is the observation
    /// that would distinguish them; the real-data suite reports the count.
    struct VendorValues: Equatable {
        static let byteCount = 12

        let startHour: UInt16
        let endHour: UInt16
        let radius: UInt16
        let onlyBuysStolenItems: Bool
        let notSellBuy: Bool
    }

    /// PLVD, 12 bytes: where the vendor trades. The middle word's meaning is
    /// decided by `type`, and the type registry is package-location shared
    /// (issue #506), so the word stays raw here.
    struct VendorLocation: Equatable {
        static let byteCount = 12

        let type: Int32
        let value: UInt32
        let radius: Int32
    }

    let formID: FormID
    let editorID: String?
    let name: LString?
    let relations: [Relation]
    let flags: Flags
    /// JAIL — exterior jail marker REFR.
    let exteriorJailMarker: FormID?
    /// WAIT — the marker the player's followers wait at.
    let followerWaitMarker: FormID?
    /// STOL — the container stolen goods are confiscated into.
    let evidenceChest: FormID?
    /// PLCN — the container the player's own inventory is held in.
    let playerInventoryContainer: FormID?
    /// CRGR — FLST of factions that share this one's crimes.
    let sharedCrimeFactionList: FormID?
    /// JOUT — the OTFT the jailed player wears.
    let jailOutfit: FormID?
    let crimeValues: CrimeValues?
    let ranks: [Rank]
    /// VEND — FLST of what the vendor buys and sells.
    let vendorBuySellList: FormID?
    /// VENC — the merchant's REFR container.
    let merchantContainer: FormID?
    let vendorValues: VendorValues?
    let vendorLocation: VendorLocation?
    /// The trailing CITC/CTDA run: the vendor trades only while these hold.
    let vendorConditions: ConditionList
    let skipped: FactionDecodeTally

    var isVendor: Bool {
        flags.contains(.vendor)
    }

    var tracksCrime: Bool {
        flags.contains(.trackCrime)
    }

    var displayName: String {
        switch name {
        case let .inline(value): value
        case .tableID, nil: editorID ?? formID.description
        }
    }

    /// The title one rank shows, preferring the gendered one the caller asked
    /// for and falling back to the other when the record only authored one.
    func rankTitle(_ index: UInt32, female: Bool) -> LString? {
        guard let rank = ranks.first(where: { $0.index == index }) else { return nil }
        return female
            ? rank.femaleTitle ?? rank.maleTitle
            : rank.maleTitle ?? rank.femaleTitle
    }

    init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "FACT" else {
            throw ESMError.malformed("expected FACT record, got \(record.type)")
        }
        var fields = FactionFields(localized: localized)
        for field in try record.fields() {
            fields.decode(field)
        }
        fields.finishRank()
        formID = FormID(record.formID)
        editorID = fields.editorID
        name = fields.name
        relations = fields.relations
        flags = fields.flags
        exteriorJailMarker = fields.links.exteriorJailMarker
        followerWaitMarker = fields.links.followerWaitMarker
        evidenceChest = fields.links.evidenceChest
        playerInventoryContainer = fields.links.playerInventoryContainer
        sharedCrimeFactionList = fields.links.sharedCrimeFactionList
        jailOutfit = fields.links.jailOutfit
        crimeValues = fields.crimeValues
        ranks = fields.ranks
        vendorBuySellList = fields.links.vendorBuySellList
        merchantContainer = fields.links.merchantContainer
        vendorValues = fields.vendorValues
        vendorLocation = fields.vendorLocation
        vendorConditions = fields.vendorConditions
        skipped = fields.skipped
    }
}
