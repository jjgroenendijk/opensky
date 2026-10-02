// EXPL explosion and DEBR debris. EXPL DATA grows over form versions, so the
// trailing members are optional. Layout and sources: docs/formats/explosions.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct Explosion: Equatable, Sendable {
    /// DATA: 40, 44, 48, or 52 bytes.
    public struct Properties: Equatable, Sendable {
        public let light: FormID?
        public let sound1: FormID?
        public let sound2: FormID?
        public let impactDataSet: FormID?
        /// Any base object the explosion places.
        public let placedObject: FormID?
        public let spawnProjectile: FormID?
        public let force: Float
        public let damage: Float
        public let radius: Float
        public let imageSpaceRadius: Float
        public let verticalOffsetMultiplier: Float?
        /// 0x02 world orientation, 0x04 always knock down, 0x08 knock down by
        /// formula, 0x10 ignore LOS, 0x20 push source only, 0x40 ignore image-space
        /// swap, 0x80 chain, 0x100 no controller vibration.
        public let flags: UInt32?
        /// 0 loud, 1 normal, 2 silent, 3 very loud.
        public let soundLevel: UInt32?
        public let size: Int
    }

    public let formID: FormID
    public let editorID: String?
    public let bounds: ObjectBounds?
    public let name: LString?
    public let model: ModelData?
    /// EITM, an ENCH or SPEL applied to what the blast hits.
    public let enchantment: FormID?
    /// MNAM, an IMAD.
    public let imageSpaceModifier: FormID?
    public let properties: Properties?
    public let scriptData: ScriptData
    public let skipped: FieldTally

    public init(record: ESMRecord, localized: Bool) throws {
        var fields = try RecordFields(record: record, type: "EXPL", localized: localized)
        formID = fields.formID
        editorID = fields.editorID()
        bounds = fields.bounds()
        name = fields.lstring("FULL")
        model = fields.model()
        enchantment = fields.formID("EITM")
        imageSpaceModifier = fields.formID("MNAM")
        properties = fields.read("DATA") { try Properties(&$0) }
        scriptData = fields.scriptData()
        skipped = fields.finish()
    }
}

nonisolated extension Explosion.Properties {
    init(_ reader: inout BinaryReader) throws {
        size = reader.bytesRemaining
        light = try reader.readFormID().nonNull
        sound1 = try reader.readFormID().nonNull
        sound2 = try reader.readFormID().nonNull
        impactDataSet = try reader.readFormID().nonNull
        placedObject = try reader.readFormID().nonNull
        spawnProjectile = try reader.readFormID().nonNull
        force = try reader.readFloat32()
        damage = try reader.readFloat32()
        radius = try reader.readFloat32()
        imageSpaceRadius = try reader.readFloat32()
        verticalOffsetMultiplier = reader.bytesRemaining >= 4 ? try reader.readFloat32() : nil
        flags = reader.bytesRemaining >= 4 ? try reader.readUInt32() : nil
        soundLevel = reader.bytesRemaining >= 4 ? try reader.readUInt32() : nil
    }
}

nonisolated public struct Debris: Equatable, Sendable {
    /// One DATA entry and the MODT that follows it.
    public struct Model: Equatable, Sendable {
        public let percentage: UInt8
        public let path: String
        public let hasCollision: Bool
        public var textureHashes: Data?
    }

    public let formID: FormID
    public let editorID: String?
    public let models: [Model]
    public let skipped: FieldTally

    public init(record: ESMRecord) throws {
        var fields = try RecordFields(record: record, type: "DEBR")
        formID = fields.formID
        editorID = fields.editorID()
        var models: [Model] = []
        for index in fields.fields.indices {
            switch fields.fields[index].type {
            case "DATA":
                if let model = fields.read(at: index, { try Model(&$0) }) {
                    models.append(model)
                }
            case "MODT" where !models.isEmpty:
                models[models.count - 1].textureHashes =
                    fields.read(at: index) { try $0.read(count: $0.bytesRemaining) }
            default:
                continue
            }
        }
        self.models = models
        skipped = fields.finish()
    }
}

nonisolated extension Debris.Model {
    /// DATA: uint8 percentage, zstring path, uint8 collision flag.
    init(_ reader: inout BinaryReader) throws {
        percentage = try reader.readUInt8()
        path = try reader.readZString()
        hasCollision = try reader.readUInt8() != 0
        textureHashes = nil
    }
}
