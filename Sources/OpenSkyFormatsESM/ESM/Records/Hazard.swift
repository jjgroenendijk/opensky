// HAZD hazard: a lingering area effect such as a fire or a frost cloud that a
// spell, explosion, or trap leaves behind. Layout and sources: docs/formats/hazards.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct Hazard: Equatable, Sendable {
    /// DATA, 40 bytes.
    public struct Properties: Equatable, Sendable {
        public let limit: UInt32
        public let radius: Float
        public let lifetime: Float
        public let imageSpaceRadius: Float
        public let targetInterval: Float
        public let flags: UInt32
        /// A SPEL or ENCH.
        public let spell: FormID?
        public let light: FormID?
        public let impactDataSet: FormID?
        public let sound: FormID?

        public var affectsPlayerOnly: Bool {
            flags & 0x01 != 0
        }

        public var inheritsDurationFromSpell: Bool {
            flags & 0x02 != 0
        }

        public var alignsToImpactNormal: Bool {
            flags & 0x04 != 0
        }

        public var inheritsRadiusFromSpell: Bool {
            flags & 0x08 != 0
        }

        public var dropsToGround: Bool {
            flags & 0x10 != 0
        }

        init(_ reader: inout BinaryReader) throws {
            limit = try reader.readUInt32()
            radius = try reader.readFloat32()
            lifetime = try reader.readFloat32()
            imageSpaceRadius = try reader.readFloat32()
            targetInterval = try reader.readFloat32()
            flags = try reader.readUInt32()
            spell = try reader.readFormID().nonNull
            light = try reader.readFormID().nonNull
            impactDataSet = try reader.readFormID().nonNull
            sound = try reader.readFormID().nonNull
        }
    }

    public let formID: FormID
    public let editorID: String?
    public let bounds: ObjectBounds?
    public let name: LString?
    public let model: ModelData?
    /// MNAM, an IMAD.
    public let imageSpaceModifier: FormID?
    /// Nil when DATA is missing or short.
    public let properties: Properties?
    public let skipped: FieldTally

    public init(record: ESMRecord, localized: Bool) throws {
        var fields = try RecordFields(record: record, type: "HAZD", localized: localized)
        formID = fields.formID
        editorID = fields.editorID()
        bounds = fields.bounds()
        name = fields.lstring("FULL")
        model = fields.model()
        imageSpaceModifier = fields.formID("MNAM")
        properties = fields.read("DATA") { try Properties(&$0) }
        skipped = fields.finish()
    }
}
