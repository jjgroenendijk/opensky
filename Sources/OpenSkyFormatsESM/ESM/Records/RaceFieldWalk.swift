// The ordered field walk behind `RaceDetails`. MNAM and FNAM pick the sex.
// NAM1 starts the body models, NAM3 the behavior graphs, NAM0 the head data,
// so the same signature (MODL, INDX) lands in the block it sits in.

import Foundation
import OpenSkyFormatsCore

nonisolated struct RaceFieldWalk {
    private enum Section {
        case skeleton, body, behavior, head
    }

    private enum Sex {
        case male, female
    }

    private var fields: RecordFields
    private var details = RaceDetails()
    private var section = Section.skeleton
    private var sex: Sex?
    private var declaredSpellCount: UInt32?
    private var spellCount = 0

    init(record: ESMRecord, localized: Bool) throws {
        fields = try RecordFields(record: record, type: "RACE", localized: localized)
    }

    mutating func run() -> (RaceDetails, FieldTally) {
        details.attacks = fields.attacks()
        for index in fields.fields.indices where !fields.isUsed(at: index) {
            if marker(at: index) || linkField(at: index) || topField(at: index) {
                continue
            }
            if !listField(at: index) {
                sectionField(at: index)
            }
        }
        if let declaredSpellCount, declaredSpellCount != spellCount {
            fields.note(.mismatch("RACE SPCT differs from the SPLO count"))
        }
        return (details, fields.finish())
    }

    // MARK: - Markers and single fields

    private mutating func marker(at index: Int) -> Bool {
        switch fields.fields[index].type {
        case "NAM1": section = .body
        case "NAM3": section = .behavior
        case "NAM0": section = .head
        case "NAM2": break
        case "MNAM": sex = .male
        case "FNAM": sex = .female
        default: return false
        }
        if ["NAM1", "NAM3", "NAM0"].contains(fields.fields[index].type) {
            sex = nil
        }
        fields.markUsed(at: index)
        return true
    }

    private mutating func linkField(at index: Int) -> Bool {
        let type = fields.fields[index].type
        if let path = Self.links[type] {
            details[keyPath: path] = link(index)
        } else if let path = Self.pairs[type] {
            details[keyPath: path] = fields.read(at: index) { reader in
                try GenderPair(
                    male: reader.readFormID().nonNull,
                    female: reader.readFormID().nonNull
                )
            }
        } else if let path = Self.arrays[type] {
            details[keyPath: path] = fields.read(at: index) { try Self.formIDs(&$0) } ?? []
        } else if Self.baseMovementTypes.contains(type) {
            details.baseMovement[type] = link(index)
        } else if Self.decodedByRace.contains(type) {
            fields.markUsed(at: index)
        } else {
            return false
        }
        return true
    }

    private mutating func topField(at index: Int) -> Bool {
        let field = fields.fields[index]
        let localized = fields.localized
        switch field.type {
        case "DESC":
            details.description = fields.read(at: index) { _ in
                try LString(field: field, localized: localized)
            }
        case "DATA": details.properties = fields.read(at: index) { try RaceProperties(&$0) }
        case "TINL": details.tintCount = fields.read(at: index) { try $0.readUInt16() }
        case "PNAM": details.faceGenMainClamp = fields.read(at: index) { try $0.readFloat32() }
        case "UNAM": details.faceGenFaceClamp = fields.read(at: index) { try $0.readFloat32() }
        case "VNAM": details.equipmentFlags = fields.read(at: index) { try $0.readUInt32() }
        case "SPCT": declaredSpellCount = fields.read(at: index) { try $0.readUInt32() }
        case "SPLO":
            fields.markUsed(at: index)
            spellCount += 1
        default: return false
        }
        return true
    }

    // MARK: - Repeated fields

    private mutating func listField(at index: Int) -> Bool {
        switch fields.fields[index].type {
        case "QNAM": details.equipSlots += one(index) { try $0.readFormID() }
        case "NAME": details.bipedObjectNames += one(index) { try $0.readZString() }
        case "MTNM": details.movementTypeNames += one(index) { try Self.fourCharacters(&$0) }
        case "PHTN": details.phonemeTargetNames += one(index) { try $0.readZString() }
        case "PHWT": details.phonemeWeights += one(index) { try Self.floats(&$0) }
        case "MTYP":
            let type = link(index)
            details.movementTypes.append(RaceMovementType(movementType: type))
        case "SPED" where !details.movementTypes.isEmpty:
            let overrides = fields.read(at: index) { try Self.floats(&$0) } ?? []
            details.movementTypes[details.movementTypes.count - 1].overrides = overrides
        default: return false
        }
        return true
    }

    // MARK: - Sectioned fields

    private mutating func sectionField(at index: Int) {
        guard let sex else { return }
        let type = fields.fields[index].type
        switch (section, type) {
        case (.skeleton, "ANAM"):
            details.skeletons[keyPath: Self.side(sex)] = fields.model(at: index)
        case (.body, "INDX"):
            let part = fields.read(at: index) { try $0.readUInt32() } ?? 0
            details.bodyParts[keyPath: Self.side(sex)].append(RaceBodyPart(index: part))
        case (.body, "MODL") where !details.bodyParts[keyPath: Self.side(sex)].isEmpty:
            let model = fields.model(at: index)
            let count = details.bodyParts[keyPath: Self.side(sex)].count
            details.bodyParts[keyPath: Self.side(sex)][count - 1].model = model
        case (.behavior, "MODL"):
            details.behaviorGraphs[keyPath: Self.side(sex)] = fields.model(at: index)
        case (.head, _):
            var head = details.headData[keyPath: Self.side(sex)]
            headField(at: index, into: &head)
            details.headData[keyPath: Self.side(sex)] = head
        default:
            return
        }
    }

    private mutating func headField(at index: Int, into head: inout RaceHeadData) {
        switch fields.fields[index].type {
        case "INDX":
            let part = fields.read(at: index) { try $0.readUInt32() } ?? 0
            head.headParts.append(RaceHeadPart(index: part))
        case "HEAD" where !head.headParts.isEmpty:
            head.headParts[head.headParts.count - 1].part = link(index)
        case "MODL": head.model = fields.model(at: index)
        case "MPAI":
            head.morphs.append(RaceMorphGroup(index: fields.read(at: index) { try Self.rest(&$0) }))
        case "MPAV":
            if head.morphs.last?.variants != nil || head.morphs.isEmpty {
                head.morphs.append(RaceMorphGroup())
            }
            head.morphs[head.morphs.count - 1].variants = fields
                .read(at: index) { try Self.rest(&$0) }
        case "DFTM", "DFTF": head.defaultFaceTexture = link(index)
        default: headListField(at: index, into: &head)
        }
    }

    private mutating func headListField(at index: Int, into head: inout RaceHeadData) {
        let type = fields.fields[index].type
        if ["RPRM", "RPRF"].contains(type) {
            head.presets += one(index) { try $0.readFormID() }
        } else if ["AHCM", "AHCF"].contains(type) {
            head.hairColors += one(index) { try $0.readFormID() }
        } else if ["FTSM", "FTSF"].contains(type) {
            head.faceDetailTextures += one(index) { try $0.readFormID() }
        } else {
            tintField(at: index, into: &head.tintMasks)
        }
    }

    private mutating func tintField(at index: Int, into masks: inout [RaceTintMask]) {
        let type = fields.fields[index].type
        if type == "TINI" {
            masks.append(RaceTintMask(index: fields.read(at: index) { try $0.readUInt16() }))
            return
        }
        guard !masks.isEmpty else { return }
        let last = masks.count - 1
        switch type {
        case "TINT": masks[last].texturePath = fields.read(at: index) { try $0.readZString() }
        case "TINP": masks[last].maskType = fields.read(at: index) { try $0.readUInt16() }
        case "TIND": masks[last].presetDefault = link(index)
        case "TINC":
            let color = link(index)
            masks[last].presets.append(RaceTintPreset(color: color))
        case "TINV" where !masks[last].presets.isEmpty:
            let preset = masks[last].presets.count - 1
            masks[last].presets[preset].defaultValue = fields
                .read(at: index) { try $0.readFloat32() }
        case "TIRS" where !masks[last].presets.isEmpty:
            let preset = masks[last].presets.count - 1
            masks[last].presets[preset].index = fields.read(at: index) { try $0.readUInt16() }
        default:
            return
        }
    }

    // MARK: - Tables and readers

    private mutating func one<Value>(
        _ index: Int,
        _ decode: (inout BinaryReader) throws -> Value
    ) -> [Value] {
        fields.read(at: index, decode).map { [$0] } ?? []
    }

    private mutating func link(_ index: Int) -> FormID? {
        fields.read(at: index) { try $0.readFormID() }?.nonNull
    }

    private static func side<Value>(_ sex: Sex) -> WritableKeyPath<GenderPair<Value>, Value> {
        sex == .male ? \.male : \.female
    }

    /// Key paths are not Sendable, so these tables are built on each use.
    private static var links: [FourCC: WritableKeyPath<RaceDetails, FormID?>] {
        [
            "ATKR": \.attackRace, "GNAM": \.bodyPartData, "NAM4": \.materialType,
            "NAM5": \.impactDataSet, "NAM7": \.decapitationEffect, "ONAM": \.openLootSound,
            "LNAM": \.closeLootSound, "UNES": \.unarmedEquipSlot, "NAM8": \.morphRace,
            "RNAM": \.armorRace
        ]
    }

    private static var pairs: [FourCC: WritableKeyPath<RaceDetails, GenderPair<FormID?>?>] {
        [
            "VTCK": \.voices, "DNAM": \.decapitateArmors, "HCLF": \.defaultHairColors
        ]
    }

    private static var arrays: [FourCC: WritableKeyPath<RaceDetails, [FormID]>] {
        [
            "KWDA": \.keywords, "HNAM": \.hairs, "ENAM": \.eyes
        ]
    }

    private static let baseMovementTypes: Set<FourCC> = [
        "WKMV", "RNMV", "SWMV", "FLMV", "SNMV", "SPMV"
    ]

    /// Fields `Race` already decodes. KSIZ is implied by the KWDA length.
    private static let decodedByRace: Set<FourCC> = ["EDID", "FULL", "WNAM", "BOD2", "BODT", "KSIZ"]

    private static func formIDs(_ reader: inout BinaryReader) throws -> [FormID] {
        var ids: [FormID] = []
        while reader.bytesRemaining >= 4 {
            try ids.append(reader.readFormID())
        }
        return ids
    }

    private static func floats(_ reader: inout BinaryReader) throws -> [Float] {
        var values: [Float] = []
        while reader.bytesRemaining >= 4 {
            try values.append(reader.readFloat32())
        }
        return values
    }

    private static func rest(_ reader: inout BinaryReader) throws -> Data {
        try reader.read(count: reader.bytesRemaining)
    }

    private static func fourCharacters(_ reader: inout BinaryReader) throws -> String {
        let start = reader.offset
        let bytes = try reader.read(count: reader.bytesRemaining)
        guard let text = TextDecoding.gameText.decode(bytes) else {
            throw BinaryReaderError.invalidString(offset: start)
        }
        return text
    }
}
