// FACT's field pass, split out of `Faction.swift` so both stay inside the
// strict lint caps. Field-by-field spec citations live at the parse sites in
// this file; the record-level references are in `Faction.swift`.

import Foundation

/// Accumulator for one FACT record's fields.
///
/// Rank groups are the only stateful part: RNAM opens a rank and the MNAM /
/// FNAM that follow belong to it, so an incoming RNAM (and the end of the
/// record) closes the one in progress. A stray MNAM before any RNAM has no
/// rank to attach to and is tallied rather than dropped silently.
nonisolated struct FactionFields {
    /// The FormID-valued links, grouped so the struct that carries them into
    /// `Faction` stays inside the parameter-count cap.
    struct Links: Equatable {
        var exteriorJailMarker: FormID?
        var followerWaitMarker: FormID?
        var evidenceChest: FormID?
        var playerInventoryContainer: FormID?
        var sharedCrimeFactionList: FormID?
        var jailOutfit: FormID?
        var vendorBuySellList: FormID?
        var merchantContainer: FormID?
    }

    let localized: Bool
    var editorID: String?
    var name: LString?
    var relations: [Faction.Relation] = []
    var flags = Faction.Flags()
    var links = Links()
    var crimeValues: Faction.CrimeValues?
    var ranks: [Faction.Rank] = []
    var vendorValues: Faction.VendorValues?
    var vendorLocation: Faction.VendorLocation?
    var vendorConditions = ConditionList()
    var skipped = FactionDecodeTally()

    private var pendingRank: Faction.Rank?

    init(localized: Bool) {
        self.localized = localized
    }

    /// A malformed field costs its own value, never the record: every throw
    /// from the readers below lands here as one tally entry.
    mutating func decode(_ field: ESMField) {
        do {
            try decodeIdentity(field)
        } catch {
            skipped.noteMalformed(field.type)
        }
    }

    /// Closes the rank group left open by the last RNAM. The record decode
    /// calls this once the field loop ends.
    mutating func finishRank() {
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
