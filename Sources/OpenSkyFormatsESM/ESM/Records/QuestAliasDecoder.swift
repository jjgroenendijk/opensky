// Field decode inside one ALST/ALLS alias group; ordering rules are in
// Quest.swift. Most alias fields are one 4-byte word in one slot, so they go
// through the tables below instead of thirty switch cases.

import Foundation
import OpenSkyFormatsCore

/// An immutable subrecord-to-slot table, shared as a `static let` constant.
nonisolated private struct AliasSlotTable<Value>: Sendable {
    typealias Slot = Sendable & WritableKeyPath<Quest.Alias, Value>

    private let slots: [FourCC: Slot]

    init(_ slots: [FourCC: Slot]) {
        self.slots = slots
    }

    subscript(code: FourCC) -> Slot? {
        slots[code]
    }
}

nonisolated extension Quest.Alias {
    /// Subrecords carrying exactly one FormID.
    private static let formIDSlots = AliasSlotTable<FormID?>([
        "ALFR": \.forcedReference,
        "ALUA": \.uniqueActor,
        "ALFL": \.forcedLocation,
        "ALRT": \.referenceType,
        "KNAM": \.keyword,
        "ALEQ": \.externalQuest,
        "ALCO": \.createdObject,
        "ALDN": \.displayName,
        "VTCK": \.voiceTypes,
        "SPOR": \.spectatorOverride,
        "OCOR": \.observeDeadBodyOverride,
        "GWOR": \.guardWarnOverride,
        "ECOR": \.combatOverride
    ])

    /// Subrecords carrying one signed alias ID. xEdit types these int32 and
    /// spells -1 as "no alias".
    private static let aliasIDSlots = AliasSlotTable<Int32?>([
        "ALFI": \.forceIntoAlias,
        "ALFA": \.aliasReference,
        "ALEA": \.externalAlias,
        "ALNA": \.nearAlias
    ])

    /// Subrecords carrying one unsigned enumeration or packed word.
    private static let wordSlots = AliasSlotTable<UInt32?>([
        "ALCA": \.createAt,
        "ALCL": \.createLevel,
        "ALNT": \.nearType,
        "ALFE": \.fromEvent,
        "ALFD": \.eventData
    ])

    /// Subrecords that repeat, each adding one FormID to a list.
    private static let formIDLists = AliasSlotTable<[FormID]>([
        "ALSP": \.spells,
        "ALFC": \.factions,
        "ALPC": \.packages
    ])

    /// Consumes one subrecord of the open alias group. Every failure costs the
    /// subrecord and nothing more; the caller keeps the alias either way.
    public mutating func decode(field: ESMField, tally: inout QuestTally) throws {
        if try decodeSlot(field, tally: &tally) {
            return
        }
        var reader = BinaryReader(field.data)
        switch field.type {
        case "ALID":
            name = try reader.readZString()
        case "FNAM":
            guard field.data.count >= 4 else { return tally.note(.malformedField(field.type)) }
            flags = try Flags(rawValue: reader.readUInt32())
        case "COCT":
            guard field.data.count >= 4 else { return tally.note(.malformedField(field.type)) }
            declaredItemCount = try reader.readUInt32()
        case "CNTO":
            guard field.data.count >= 8 else { return tally.note(.malformedField(field.type)) }
            let item = try FormID(reader.readUInt32())
            try items.append(Item(item: item, count: Int32(bitPattern: reader.readUInt32())))
        default:
            if try keywords.decode(field: field) {
                return
            }
            if try matchConditions.decode(field: field) {
                return
            }
            tally.note(.unknownField(field.type))
        }
    }

    /// The single-word subrecords, resolved through the slot tables above.
    private mutating func decodeSlot(_ field: ESMField, tally: inout QuestTally) throws -> Bool {
        let formIDPath = Self.formIDSlots[field.type]
        let aliasPath = Self.aliasIDSlots[field.type]
        let wordPath = Self.wordSlots[field.type]
        let listPath = Self.formIDLists[field.type]
        guard formIDPath != nil || aliasPath != nil || wordPath != nil || listPath != nil else {
            return false
        }
        guard field.data.count >= 4 else {
            tally.note(.malformedField(field.type))
            return true
        }
        var reader = BinaryReader(field.data)
        let word = try reader.readUInt32()
        if let formIDPath {
            self[keyPath: formIDPath] = FormID(word)
        } else if let aliasPath {
            self[keyPath: aliasPath] = Int32(bitPattern: word)
        } else if let wordPath {
            self[keyPath: wordPath] = word
        } else if let listPath {
            self[keyPath: listPath].append(FormID(word))
        }
        return true
    }
}
