// FACT faction: relations, crime response, ranks, and vendor data, as links
// and raw values. Variable-size structs decode by payload length, so an older
// or longer struct loses fields instead of failing the record.
// Layout and sources: docs/formats/factions.md.

import Foundation
public import OpenSkyFormatsCore

nonisolated public struct FactionDecodeTally: Equatable, RankedSkipReport {
    public var ranked: [(name: String, count: Int)] {
        Self.rank([
            ("unknown", unknownFields),
            ("malformed", malformedFields),
            ("trailing bytes", trailingBytes)
        ])
    }

    public private(set) var malformedFields: [FourCC: Int] = [:]
    private(set) var unknownFields: [FourCC: Int] = [:]
    /// Bytes past the last whole element of a packed array, or past the last
    /// documented member of a struct that arrived longer than the spec.
    private(set) var trailingBytes: [FourCC: Int] = [:]
    /// VENV offset 6, which xEdit calls "Unknown 1" and UESP folds into a
    /// 32-bit radius. Counted whenever it is nonzero, because a nonzero word
    /// there is the only observation that could tell the two readings apart.
    private(set) var vendorRadiusHighWordSet = 0

    public var total: Int {
        malformedFields.values.reduce(0, +)
            + unknownFields.values.reduce(0, +)
            + trailingBytes.values.reduce(0, +)
    }

    public mutating func noteMalformed(_ type: FourCC) {
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
        static let byteCount = 12

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
        static let requiredByteCount = 12
        static let withStealMultiplierByteCount = 16
        public static let fullByteCount = 20

        public let arrest: Bool
        public let attackOnSight: Bool
        public let murder: UInt16
        public let assault: UInt16
        public let trespass: UInt16
        public let pickpocket: UInt16
        /// Offset 10. Both sources call it unused and observe nonzero values,
        /// so it is kept verbatim and never read as a gold amount.
        let unknown: UInt16
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
        static let byteCount = 12

        public let startHour: UInt16
        public let endHour: UInt16
        public let radius: UInt16
        public let onlyBuysStolenItems: Bool
        public let notSellBuy: Bool
    }

    /// PLVD, 12 bytes: where the vendor trades. The middle word's meaning
    /// depends on `type`, so it stays raw here.
    public struct VendorLocation: Equatable, Sendable {
        static let byteCount = 12

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

/// Accumulator for one FACT record's fields.
///
/// Rank groups are the only stateful part: RNAM opens a rank and the MNAM /
/// FNAM that follow belong to it, so an incoming RNAM (and the end of the
/// record) closes the one in progress. A stray MNAM before any RNAM has no
/// rank to attach to and is tallied rather than dropped silently.
nonisolated public struct FactionFields: Sendable {
    /// The FormID-valued links, grouped so the struct that carries them into
    /// `Faction` stays inside the parameter-count cap.
    public struct Links: Equatable, Sendable {
        public var exteriorJailMarker: FormID?
        public var followerWaitMarker: FormID?
        public var evidenceChest: FormID?
        public var playerInventoryContainer: FormID?
        public var sharedCrimeFactionList: FormID?
        public var jailOutfit: FormID?
        public var vendorBuySellList: FormID?
        public var merchantContainer: FormID?
    }

    public let localized: Bool
    public var editorID: String?
    public var name: LString?
    public var relations: [Faction.Relation] = []
    public var flags = Faction.Flags()
    public var links = Links()
    public var crimeValues: Faction.CrimeValues?
    public var ranks: [Faction.Rank] = []
    public var vendorValues: Faction.VendorValues?
    public var vendorLocation: Faction.VendorLocation?
    public var vendorConditions = ConditionList()
    public var skipped = FactionDecodeTally()

    private var pendingRank: Faction.Rank?

    public init(localized: Bool) {
        self.localized = localized
    }

    /// A malformed field costs its own value, never the record: every throw
    /// from the readers below lands here as one tally entry.
    public mutating func decode(_ field: ESMField) {
        do {
            try decodeIdentity(field)
        } catch {
            skipped.noteMalformed(field.type)
        }
    }

    /// Closes the rank group left open by the last RNAM. The record decode
    /// calls this once the field loop ends.
    public mutating func finishRank() {
        if let pendingRank {
            ranks.append(pendingRank)
        }
        pendingRank = nil
    }

    private mutating func decodeIdentity(_ field: ESMField) throws {
        switch field.type {
        case "EDID":
            var reader = BinaryReader(field.data)
            editorID = try reader.readZString()
        case "FULL":
            name = try LString(field: field, localized: localized)
        case "XNAM":
            try relations.append(contentsOf: decodeRelations(field))
        case "DATA":
            flags = try Faction.Flags(rawValue: scalarWord(field))
        case "CRVA":
            crimeValues = try decodeCrimeValues(field)
        default:
            try decodeRank(field)
        }
    }

    private mutating func decodeRank(_ field: ESMField) throws {
        switch field.type {
        case "RNAM":
            finishRank()
            pendingRank = try Faction.Rank(index: scalarWord(field))
        case "MNAM":
            try setTitle(field, keyPath: \.maleTitle)
        case "FNAM":
            try setTitle(field, keyPath: \.femaleTitle)
        default:
            try decodeVendor(field)
        }
    }

    private mutating func decodeVendor(_ field: ESMField) throws {
        switch field.type {
        case "VENV":
            vendorValues = try decodeVendorValues(field)
        case "PLVD":
            vendorLocation = try decodeVendorLocation(field)
        default:
            try decodeLink(field)
        }
    }

    private mutating func decodeLink(_ field: ESMField) throws {
        switch field.type {
        case "JAIL": links.exteriorJailMarker = try scalarLink(field)
        case "WAIT": links.followerWaitMarker = try scalarLink(field)
        case "STOL": links.evidenceChest = try scalarLink(field)
        case "PLCN": links.playerInventoryContainer = try scalarLink(field)
        case "CRGR": links.sharedCrimeFactionList = try scalarLink(field)
        case "JOUT": links.jailOutfit = try scalarLink(field)
        case "VEND": links.vendorBuySellList = try scalarLink(field)
        case "VENC": links.merchantContainer = try scalarLink(field)
        default:
            // The trailing CITC/CTDA/CIS1/CIS2 run is the vendor's condition
            // list; anything else is a field this decoder does not read.
            if try !vendorConditions.decode(field: field) {
                skipped.noteUnknown(field.type)
            }
        }
    }

    /// XNAM, repeated, 12 bytes each: FACT or RACE link, signed modifier, and
    /// the combat-reaction word (xEdit `wbFactionRelations`).
    private mutating func decodeRelations(_ field: ESMField) throws -> [Faction.Relation] {
        let stride = Faction.Relation.byteCount
        skipped.noteTail(field.type, bytes: field.data.count % stride)
        var reader = BinaryReader(field.data)
        var values: [Faction.Relation] = []
        values.reserveCapacity(field.data.count / stride)
        for _ in 0 ..< (field.data.count / stride) {
            try values.append(Faction.Relation(
                faction: FormID(reader.readUInt32()),
                modifier: Int32(bitPattern: reader.readUInt32()),
                reaction: Faction.CombatReaction(rawValue: reader.readUInt32())
            ))
        }
        return values
    }

    /// CRVA, 12 / 16 / 20 bytes. The tail fields are read only when the payload
    /// reaches them, which is how a record written at an older record version
    /// keeps the fields it does carry.
    private mutating func decodeCrimeValues(_ field: ESMField) throws -> Faction.CrimeValues {
        guard field.data.count >= Faction.CrimeValues.requiredByteCount else {
            throw ESMError.malformed(
                "FACT CRVA has \(field.data.count) bytes, expected at least "
                    + "\(Faction.CrimeValues.requiredByteCount)"
            )
        }
        skipped.noteTail(
            field.type,
            bytes: field.data.count - min(field.data.count, Faction.CrimeValues.fullByteCount)
        )
        var reader = BinaryReader(field.data)
        let arrest = try reader.readUInt8() != 0
        let attackOnSight = try reader.readUInt8() != 0
        let murder = try reader.readUInt16()
        let assault = try reader.readUInt16()
        let trespass = try reader.readUInt16()
        let pickpocket = try reader.readUInt16()
        let unknown = try reader.readUInt16()
        let hasMultiplier = field.data.count >= Faction.CrimeValues.withStealMultiplierByteCount
        let hasTail = field.data.count >= Faction.CrimeValues.fullByteCount
        return try Faction.CrimeValues(
            arrest: arrest,
            attackOnSight: attackOnSight,
            murder: murder,
            assault: assault,
            trespass: trespass,
            pickpocket: pickpocket,
            unknown: unknown,
            stealMultiplier: hasMultiplier ? reader.readFloat32() : nil,
            escape: hasTail ? reader.readUInt16() : nil,
            werewolf: hasTail ? reader.readUInt16() : nil
        )
    }

    /// VENV, 12 bytes. See `Faction.VendorValues` for the xEdit / UESP
    /// disagreement about the radius width that the tally here measures.
    private mutating func decodeVendorValues(_ field: ESMField) throws -> Faction.VendorValues {
        guard field.data.count >= Faction.VendorValues.byteCount else {
            throw ESMError.malformed(
                "FACT VENV has \(field.data.count) bytes, expected "
                    + "\(Faction.VendorValues.byteCount)"
            )
        }
        skipped.noteTail(field.type, bytes: field.data.count - Faction.VendorValues.byteCount)
        var reader = BinaryReader(field.data)
        let startHour = try reader.readUInt16()
        let endHour = try reader.readUInt16()
        let radius = try reader.readUInt16()
        if try reader.readUInt16() != 0 {
            skipped.noteVendorRadiusHighWord()
        }
        return try Faction.VendorValues(
            startHour: startHour,
            endHour: endHour,
            radius: radius,
            onlyBuysStolenItems: reader.readUInt8() != 0,
            notSellBuy: reader.readUInt8() != 0
        )
    }

    /// PLVD, 12 bytes: type selector, one raw word, signed radius.
    private mutating func decodeVendorLocation(
        _ field: ESMField
    ) throws -> Faction.VendorLocation {
        guard field.data.count >= Faction.VendorLocation.byteCount else {
            throw ESMError.malformed(
                "FACT PLVD has \(field.data.count) bytes, expected "
                    + "\(Faction.VendorLocation.byteCount)"
            )
        }
        skipped.noteTail(field.type, bytes: field.data.count - Faction.VendorLocation.byteCount)
        var reader = BinaryReader(field.data)
        return try Faction.VendorLocation(
            type: Int32(bitPattern: reader.readUInt32()),
            value: reader.readUInt32(),
            radius: Int32(bitPattern: reader.readUInt32())
        )
    }

    private mutating func setTitle(
        _ field: ESMField,
        keyPath: WritableKeyPath<Faction.Rank, LString?>
    ) throws {
        guard pendingRank != nil else {
            skipped.noteUnknown(field.type)
            return
        }
        pendingRank?[keyPath: keyPath] = try LString(field: field, localized: localized)
    }

    private mutating func scalarWord(_ field: ESMField) throws -> UInt32 {
        guard field.data.count >= 4 else {
            throw ESMError.malformed("FACT \(field.type) has \(field.data.count) bytes, expected 4")
        }
        var reader = BinaryReader(field.data)
        return try reader.readUInt32()
    }

    /// A null link is absent, matching how the other reference records read a
    /// zero FormID.
    private mutating func scalarLink(_ field: ESMField) throws -> FormID? {
        let value = try FormID(scalarWord(field))
        return value.isNull ? nil : value
    }
}
