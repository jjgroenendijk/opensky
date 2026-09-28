// MGEF magic-effect record. DATA is the fixed 152-byte struct used by every
// spell, enchantment, potion and ingredient effect link.
//
// References: UESP "Skyrim Mod:Mod File Format/MGEF"
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/MGEF
// Cross-checked against xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas:
//   `wbRecord(MGEF, 'Magic Effect', [...])`, including the ordered DATA struct,
//   `wbMagicEffectSounds`, DNAM and `wbConditions`.
// Layout and real-install evidence: docs/formats/magic-records.md.

import Foundation

nonisolated package struct MagicEffectFlags: OptionSet, Equatable {
    package let rawValue: UInt32

    package init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    package static let hostile = Self(rawValue: 1 << 0)
    package static let recover = Self(rawValue: 1 << 1)
    package static let detrimental = Self(rawValue: 1 << 2)
    package static let snapToNavmesh = Self(rawValue: 1 << 3)
    package static let noHitEvent = Self(rawValue: 1 << 4)
    package static let dispelWithKeywords = Self(rawValue: 1 << 8)
    package static let noDuration = Self(rawValue: 1 << 9)
    package static let noMagnitude = Self(rawValue: 1 << 10)
    package static let noArea = Self(rawValue: 1 << 11)
    package static let effectsPersist = Self(rawValue: 1 << 12)
    package static let goryVisuals = Self(rawValue: 1 << 14)
    package static let hideInUI = Self(rawValue: 1 << 15)
    package static let noRecast = Self(rawValue: 1 << 17)
    package static let powerAffectsMagnitude = Self(rawValue: 1 << 21)
    package static let powerAffectsDuration = Self(rawValue: 1 << 22)
    package static let painless = Self(rawValue: 1 << 26)
    package static let noHitEffect = Self(rawValue: 1 << 27)
    package static let noDeathDispel = Self(rawValue: 1 << 28)
}

nonisolated package struct MagicEffectSound: Equatable {
    package let kind: UInt32
    package let descriptor: FormID?
}

nonisolated package enum MagicEffectSkipKind: Hashable {
    case unknownField(FourCC)
    case malformedField(FourCC)
}

nonisolated package struct MagicEffectTally: Equatable {
    package private(set) var counts: [MagicEffectSkipKind: Int] = [:]

    package var total: Int {
        counts.values.reduce(0, +)
    }

    package mutating func note(_ kind: MagicEffectSkipKind) {
        counts[kind, default: 0] += 1
    }
}

nonisolated package struct MagicEffectData: Equatable {
    package let flags: MagicEffectFlags
    package let baseCost: Float
    package let associatedItem: FormID?
    package let magicSkill: Int32
    package let resistanceActorValue: Int32
    package let counterEffectCount: UInt16
    package let castingLight: FormID?
    package let taperWeight: Float
    package let hitShader: FormID?
    package let enchantShader: FormID?
    package let minimumSkillLevel: UInt32
    package let spellmakingArea: UInt32
    package let castingTime: Float
    package let taperCurve: Float
    package let taperDuration: Float
    package let secondActorValueWeight: Float
    package let archetype: MagicEffectArchetype
    package let relatedActorValue: Int32
    package let projectile: FormID?
    package let explosion: FormID?
    package let castingType: MagicEffectCastingType
    package let delivery: MagicEffectDelivery
    package let secondActorValue: Int32
    package let castingArt: FormID?
    package let hitEffectArt: FormID?
    package let impactData: FormID?
    package let skillUsageMultiplier: Float
    package let dualCastArt: FormID?
    package let dualCastScale: Float
    package let enchantArt: FormID?
    package let hitVisuals: FormID?
    package let enchantVisuals: FormID?
    package let equipAbility: FormID?
    package let imageSpaceModifier: FormID?
    package let perkToApply: FormID?
    package let castingSoundLevel: UInt32
    package let scriptAIScore: Float
    package let scriptAIDelay: Float

    package var unknownEnumCount: Int {
        var count = 0
        if case .unknown = archetype {
            count += 1
        }
        if case .unknown = castingType {
            count += 1
        }
        if case .unknown = delivery {
            count += 1
        }
        return count
    }

    package init(field: ESMField) throws {
        guard field.data.count == 152 else {
            throw ESMError.malformed(
                "MGEF DATA has \(field.data.count) bytes, expected exactly 152"
            )
        }
        var reader = BinaryReader(field.data)
        flags = try MagicEffectFlags(rawValue: reader.readUInt32())
        baseCost = try reader.readFloat32()
        associatedItem = try Self.readLink(&reader)
        magicSkill = try Self.readInt32(&reader)
        resistanceActorValue = try Self.readInt32(&reader)
        counterEffectCount = try reader.readUInt16()
        reader.skip(2) // unused padding; ESCE entries remain authoritative
        castingLight = try Self.readLink(&reader)
        taperWeight = try reader.readFloat32()
        hitShader = try Self.readLink(&reader)
        enchantShader = try Self.readLink(&reader)
        minimumSkillLevel = try reader.readUInt32()
        spellmakingArea = try reader.readUInt32()
        castingTime = try reader.readFloat32()
        taperCurve = try reader.readFloat32()
        taperDuration = try reader.readFloat32()
        secondActorValueWeight = try reader.readFloat32()
        archetype = try MagicEffectArchetype(rawValue: reader.readUInt32())
        relatedActorValue = try Self.readInt32(&reader)
        projectile = try Self.readLink(&reader)
        explosion = try Self.readLink(&reader)
        castingType = try MagicEffectCastingType(rawValue: reader.readUInt32())
        delivery = try MagicEffectDelivery(rawValue: reader.readUInt32())
        secondActorValue = try Self.readInt32(&reader)
        castingArt = try Self.readLink(&reader)
        hitEffectArt = try Self.readLink(&reader)
        impactData = try Self.readLink(&reader)
        skillUsageMultiplier = try reader.readFloat32()
        dualCastArt = try Self.readLink(&reader)
        dualCastScale = try reader.readFloat32()
        enchantArt = try Self.readLink(&reader)
        hitVisuals = try Self.readLink(&reader)
        enchantVisuals = try Self.readLink(&reader)
        equipAbility = try Self.readLink(&reader)
        imageSpaceModifier = try Self.readLink(&reader)
        perkToApply = try Self.readLink(&reader)
        castingSoundLevel = try reader.readUInt32()
        scriptAIScore = try reader.readFloat32()
        scriptAIDelay = try reader.readFloat32()
    }

    private static func readLink(_ reader: inout BinaryReader) throws -> FormID? {
        let id = try FormID(reader.readUInt32())
        return id.isNull ? nil : id
    }

    private static func readInt32(_ reader: inout BinaryReader) throws -> Int32 {
        try Int32(bitPattern: reader.readUInt32())
    }
}

nonisolated package struct MagicEffect: Equatable {
    package let formID: FormID
    package let editorID: String?
    package let name: LString?
    package let description: LString?
    package let menuDisplayObject: FormID?
    package let keywords: KeywordList
    package let data: MagicEffectData?
    package let counterEffects: [FormID]
    package let sounds: [MagicEffectSound]
    package let conditions: ConditionList
    package let skipped: MagicEffectTally

    package init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "MGEF" else {
            throw ESMError.malformed("expected MGEF record, got \(record.type)")
        }
        var decoder = MagicEffectFields(localized: localized)
        for field in try record.fields() {
            decoder.decode(field)
        }
        formID = FormID(record.formID)
        editorID = decoder.editorID
        name = decoder.name
        description = decoder.description
        menuDisplayObject = decoder.menuDisplayObject
        keywords = decoder.keywords
        data = decoder.data
        counterEffects = decoder.counterEffects
        sounds = decoder.sounds
        conditions = decoder.conditions
        skipped = decoder.skipped
    }

    package init(formID: FormID, editorID: String?, name: LString?, data: MagicEffectData?) {
        self.formID = formID
        self.editorID = editorID
        self.name = name
        description = nil
        menuDisplayObject = nil
        keywords = KeywordList()
        self.data = data
        counterEffects = []
        sounds = []
        conditions = ConditionList()
        skipped = MagicEffectTally()
    }
}

nonisolated private struct MagicEffectFields {
    let localized: Bool
    var editorID: String?
    var name: LString?
    var description: LString?
    var menuDisplayObject: FormID?
    var keywords = KeywordList()
    var data: MagicEffectData?
    var counterEffects: [FormID] = []
    var sounds: [MagicEffectSound] = []
    var conditions = ConditionList()
    var skipped = MagicEffectTally()

    mutating func decode(_ field: ESMField) {
        do {
            if try keywords.decode(field: field) {
                return
            }
            if try conditions.decode(field: field) {
                return
            }
            switch field.type {
            case "EDID": editorID = try Self.readString(field)
            case "FULL": name = try LString(field: field, localized: localized)
            case "DNAM": description = try LString(field: field, localized: localized)
            case "MDOB": menuDisplayObject = try Self.readLink(field)
            case "DATA": data = try MagicEffectData(field: field)
            case "ESCE": try appendCounterEffect(field)
            case "SNDD": try appendSound(field)
            case "VMAD": skipped.note(.unknownField(field.type))
            default: skipped.note(.unknownField(field.type))
            }
        } catch {
            skipped.note(.malformedField(field.type))
        }
    }

    private mutating func appendCounterEffect(_ field: ESMField) throws {
        guard let link = try Self.readLink(field) else { return }
        counterEffects.append(link)
    }

    private mutating func appendSound(_ field: ESMField) throws {
        guard !field.data.isEmpty else { return }
        guard field.data.count >= 8, field.data.count.isMultiple(of: 8) else {
            throw ESMError.malformed(
                "MGEF SNDD has \(field.data.count) bytes, expected 8-byte entries"
            )
        }
        var reader = BinaryReader(field.data)
        while reader.bytesRemaining >= 8 {
            let kind = try reader.readUInt32()
            let descriptor = try FormID(reader.readUInt32())
            sounds.append(MagicEffectSound(
                kind: kind,
                descriptor: descriptor.isNull ? nil : descriptor
            ))
        }
    }

    private static func readString(_ field: ESMField) throws -> String {
        var reader = BinaryReader(field.data)
        return try reader.readZString()
    }

    private static func readLink(_ field: ESMField) throws -> FormID? {
        guard field.data.count >= 4 else {
            throw ESMError.malformed("MGEF \(field.type) has \(field.data.count) bytes")
        }
        var reader = BinaryReader(field.data)
        let id = try FormID(reader.readUInt32())
        return id.isNull ? nil : id
    }
}
