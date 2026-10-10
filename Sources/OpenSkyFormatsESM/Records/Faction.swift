// FACT faction: relations, crime response, ranks, and vendor data, as links
// and raw values. Variable-size structs decode by payload length, so an older
// or longer struct loses fields instead of failing the record.
// Layout and sources: docs/formats/factions.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct FactionDecodeTally: Equatable, RankedSkipReport {
    public var ranked: [(name: String, count: Int)] {
        Self.rank([
            ("unknown", unknownFields),
            ("malformed", malformedFields),
            ("trailing bytes", trailingBytes)
        ])
    }

    public private(set) var malformedFields: [FourCC: Int] = [:]
    public private(set) var unknownFields: [FourCC: Int] = [:]
    /// Bytes past the last whole element of a packed array, or past the last
    /// documented member of a struct that arrived longer than the spec.
    public private(set) var trailingBytes: [FourCC: Int] = [:]
    /// VENV offset 6, which xEdit calls "Unknown 1" and UESP folds into a
    /// 32-bit radius. Counted whenever it is nonzero, because a nonzero word
    /// there is the only observation that could tell the two readings apart.
    public private(set) var vendorRadiusHighWordSet = 0

    public var total: Int {
        malformedFields.values.reduce(0, +)
            + unknownFields.values.reduce(0, +)
            + trailingBytes.values.reduce(0, +)
    }

    public mutating func noteMalformed(_ type: FourCC) {
        malformedFields[type, default: 0] += 1
    }

    public mutating func noteUnknown(_ type: FourCC) {
        unknownFields[type, default: 0] += 1
    }

    public mutating func noteTail(_ type: FourCC, bytes: Int) {
        guard bytes > 0 else { return }
        trailingBytes[type, default: 0] += bytes
    }

    public mutating func noteVendorRadiusHighWord() {
        vendorRadiusHighWordSet += 1
    }
}

nonisolated public struct Faction: Equatable, Sendable {
    /// DATA. Bit names follow xEdit, which spells out which crime each "ignore"
    /// bit covers; UESP names the same bits with the same values.
    public struct Flags: OptionSet, Equatable, Sendable {
        public let rawValue: UInt32

        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        public static let hiddenFromNPC = Flags(rawValue: 0x0000_0001)
        public static let specialCombat = Flags(rawValue: 0x0000_0002)
        public static let trackCrime = Flags(rawValue: 0x0000_0040)
        public static let ignoreMurder = Flags(rawValue: 0x0000_0080)
        public static let ignoreAssault = Flags(rawValue: 0x0000_0100)
        public static let ignoreStealing = Flags(rawValue: 0x0000_0200)
        public static let ignoreTrespass = Flags(rawValue: 0x0000_0400)
        public static let doNotReportCrimesAgainstMembers = Flags(rawValue: 0x0000_0800)
        public static let crimeGoldUseDefaults = Flags(rawValue: 0x0000_1000)
        public static let ignorePickpocket = Flags(rawValue: 0x0000_2000)
        public static let vendor = Flags(rawValue: 0x0000_4000)
        public static let canBeOwner = Flags(rawValue: 0x0000_8000)
        public static let ignoreWerewolf = Flags(rawValue: 0x0001_0000)
    }

    /// XNAM's third word: how members of the two factions treat each other.
    public enum CombatReaction: Equatable, CustomStringConvertible, Sendable {
        case neutral
        case enemy
        case ally
        case friend
        case unknown(raw: UInt32)

        public init(rawValue: UInt32) {
            switch rawValue {
            case 0: self = .neutral
            case 1: self = .enemy
            case 2: self = .ally
            case 3: self = .friend
            default: self = .unknown(raw: rawValue)
            }
        }

        public var description: String {
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
    public struct Relation: Equatable, Sendable {
        public static let byteCount = 12

        public let faction: FormID
        /// Signed disposition modifier. xEdit notes the Creation Kit no longer
        /// edits it and vanilla leaves it zero except on one record.
        public let modifier: Int32
        public let reaction: CombatReaction
    }

    /// CRVA, 12, 16 or 20 bytes. The three trailing fields came in later record
    /// versions, so they are optional: the caller decides what an absent one
    /// means, instead of a silent zero.
    public struct CrimeValues: Equatable, Sendable {
        public static let requiredByteCount = 12
        public static let withStealMultiplierByteCount = 16
        public static let fullByteCount = 20

        public let arrest: Bool
        public let attackOnSight: Bool
        public let murder: UInt16
        public let assault: UInt16
        public let trespass: UInt16
        public let pickpocket: UInt16
        /// Offset 10. Both sources call it unused and observe nonzero values,
        /// so it is kept verbatim and never read as a gold amount.
        public let unknown: UInt16
        public let stealMultiplier: Float?
        public let escape: UInt16?
        public let werewolf: UInt16?
    }

    /// One RNAM/MNAM/FNAM group. The titles are localizable, so they are
    /// `LString` and may be string-table IDs rather than text.
    public struct Rank: Equatable, Sendable {
        public let index: UInt32
        public var maleTitle: LString?
        public var femaleTitle: LString?
    }

    /// VENV, 12 bytes. The two sources disagree about offsets 4...7: xEdit
    /// reads a 16-bit radius followed by two unknown bytes, UESP a 32-bit
    /// radius. This decode follows xEdit and tallies a nonzero word at offset 6
    /// (`FactionDecodeTally.vendorRadiusHighWordSet`), which is the observation
    /// that would distinguish them; the real-data suite reports the count.
    public struct VendorValues: Equatable, Sendable {
        public static let byteCount = 12

        public let startHour: UInt16
        public let endHour: UInt16
        public let radius: UInt16
        public let onlyBuysStolenItems: Bool
        public let notSellBuy: Bool
    }

    /// PLVD, 12 bytes: where the vendor trades. The middle word's meaning
    /// depends on `type`, so it stays raw here.
    public struct VendorLocation: Equatable, Sendable {
        public static let byteCount = 12

        public let type: Int32
        public let value: UInt32
        public let radius: Int32
    }

    public let formID: FormID
    public let editorID: String?
    public let name: LString?
    public let relations: [Relation]
    public let flags: Flags
    /// JAIL — exterior jail marker REFR.
    public let exteriorJailMarker: FormID?
    /// WAIT — the marker the player's followers wait at.
    public let followerWaitMarker: FormID?
    /// STOL — the container stolen goods are confiscated into.
    public let evidenceChest: FormID?
    /// PLCN — the container the player's own inventory is held in.
    public let playerInventoryContainer: FormID?
    /// CRGR — FLST of factions that share this one's crimes.
    public let sharedCrimeFactionList: FormID?
    /// JOUT — the OTFT the jailed player wears.
    public let jailOutfit: FormID?
    public let crimeValues: CrimeValues?
    public let ranks: [Rank]
    /// VEND — FLST of what the vendor buys and sells.
    public let vendorBuySellList: FormID?
    /// VENC — the merchant's REFR container.
    public let merchantContainer: FormID?
    public let vendorValues: VendorValues?
    public let vendorLocation: VendorLocation?
    /// The trailing CITC/CTDA run: the vendor trades only while these hold.
    public let vendorConditions: ConditionList
    public let skipped: FactionDecodeTally

    public var isVendor: Bool {
        flags.contains(.vendor)
    }

    public var tracksCrime: Bool {
        flags.contains(.trackCrime)
    }

    public var displayName: String {
        switch name {
        case let .inline(value): value
        case .tableID, .pluginTableID, nil: editorID ?? formID.description
        }
    }

    /// The title one rank shows, preferring the gendered one the caller asked
    /// for and falling back to the other when the record only authored one.
    public func rankTitle(_ index: UInt32, female: Bool) -> LString? {
        guard let rank = ranks.first(where: { $0.index == index }) else { return nil }
        return female
            ? rank.femaleTitle ?? rank.maleTitle
            : rank.maleTitle ?? rank.femaleTitle
    }

    public init(record: ESMRecord, localized: Bool) throws {
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
