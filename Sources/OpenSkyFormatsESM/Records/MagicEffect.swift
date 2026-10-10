// MGEF magic-effect record. DATA is the fixed 152-byte struct every spell,
// enchantment, potion and ingredient effect links to. Layout from UESP and
// xEdit: docs/formats/magic-records.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct MagicEffectFlags: OptionSet, Equatable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let hostile = Self(rawValue: 1 << 0)
    public static let recover = Self(rawValue: 1 << 1)
    public static let detrimental = Self(rawValue: 1 << 2)
    public static let snapToNavmesh = Self(rawValue: 1 << 3)
    public static let noHitEvent = Self(rawValue: 1 << 4)
    public static let dispelWithKeywords = Self(rawValue: 1 << 8)
    public static let noDuration = Self(rawValue: 1 << 9)
    public static let noMagnitude = Self(rawValue: 1 << 10)
    public static let noArea = Self(rawValue: 1 << 11)
    public static let effectsPersist = Self(rawValue: 1 << 12)
    public static let goryVisuals = Self(rawValue: 1 << 14)
    public static let hideInUI = Self(rawValue: 1 << 15)
    public static let noRecast = Self(rawValue: 1 << 17)
    public static let powerAffectsMagnitude = Self(rawValue: 1 << 21)
    public static let powerAffectsDuration = Self(rawValue: 1 << 22)
    public static let painless = Self(rawValue: 1 << 26)
    public static let noHitEffect = Self(rawValue: 1 << 27)
    public static let noDeathDispel = Self(rawValue: 1 << 28)
}

nonisolated public struct MagicEffectSound: Equatable, Sendable {
    public let kind: UInt32
    public let descriptor: FormID?
}

nonisolated public enum MagicEffectSkipKind: SkipTallyKind {
    case unknownField(FourCC)
    case malformedField(FourCC)

    public var name: String {
        switch self {
        case let .unknownField(type): "unknown \(type)"
        case let .malformedField(type): "malformed \(type)"
        }
    }
}

public typealias MagicEffectTally = SkipTally<MagicEffectSkipKind>

nonisolated public struct MagicEffectData: Equatable, Sendable {
    public let flags: MagicEffectFlags
    public let baseCost: Float
    public let associatedItem: FormID?
    public let magicSkill: Int32
    public let resistanceActorValue: Int32
    public let counterEffectCount: UInt16
    public let castingLight: FormID?
    public let taperWeight: Float
    public let hitShader: FormID?
    public let enchantShader: FormID?
    public let minimumSkillLevel: UInt32
    public let spellmakingArea: UInt32
    public let castingTime: Float
    public let taperCurve: Float
    public let taperDuration: Float
    public let secondActorValueWeight: Float
    public let archetype: MagicEffectArchetype
    public let relatedActorValue: Int32
    public let projectile: FormID?
    public let explosion: FormID?
    public let castingType: MagicEffectCastingType
    public let delivery: MagicEffectDelivery
    public let secondActorValue: Int32
    public let castingArt: FormID?
    public let hitEffectArt: FormID?
    public let impactData: FormID?
    public let skillUsageMultiplier: Float
    public let dualCastArt: FormID?
    public let dualCastScale: Float
    public let enchantArt: FormID?
    public let hitVisuals: FormID?
    public let enchantVisuals: FormID?
    public let equipAbility: FormID?
    public let imageSpaceModifier: FormID?
    public let perkToApply: FormID?
    public let castingSoundLevel: UInt32
    public let scriptAIScore: Float
    public let scriptAIDelay: Float

    public var unknownEnumCount: Int {
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

    public init(field: ESMField) throws {
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

nonisolated public struct MagicEffect: Equatable, Sendable {
    public let formID: FormID
    public let editorID: String?
    public let name: LString?
    public let description: LString?
    public let menuDisplayObject: FormID?
    public let keywords: KeywordList
    public let data: MagicEffectData?
    public let counterEffects: [FormID]
    public let sounds: [MagicEffectSound]
    public let conditions: ConditionList
    /// VMAD — the Papyrus scripts a script-driven effect runs.
    public let scriptData: ScriptData
    public let skipped: MagicEffectTally

    public init(record: ESMRecord, localized: Bool) throws {
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
        scriptData = decoder.scriptData
        skipped = decoder.skipped
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
    var scriptData = ScriptData(ownerType: "MGEF")
    var skipped = MagicEffectTally()

    mutating func decode(_ field: ESMField) {
        do {
            if try keywords.decode(field: field) {
                return
            }
            if try conditions.decode(field: field) || scriptData.decode(field: field) {
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
