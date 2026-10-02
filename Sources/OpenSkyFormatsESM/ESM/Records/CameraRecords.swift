// CAMS camera shots and CPTH camera paths: the kill-move and VATS cameras.
// A path holds shots and sits in a tree of parent and previous links.
// Layout and sources: docs/formats/camera-records.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct CameraShot: Equatable, Sendable {
    /// DATA. Members from `target` on are optional, so DATA comes in 40 or 44 bytes.
    nonisolated public struct Properties: Equatable, Sendable {
        /// 0 shoot, 1 fly, 2 hit, 3 zoom.
        public let action: UInt32
        /// 0 attacker, 1 projectile, 2 target, 3 lead actor.
        public let location: UInt32
        public let target: UInt32?
        /// 0x01 position follows location, 0x02 rotation follows target,
        /// 0x04 no bone follow, 0x08 first person, 0x10 no tracer, 0x20 start at time zero.
        public let flags: UInt32?
        /// Time multipliers for the player, the target, and the world.
        public let timeMultipliers: SIMD3<Float>?
        public let maxTime: Float?
        public let minTime: Float?
        public let targetPercentBetweenActors: Float?
        public let nearTargetDistance: Float?

        init(_ reader: inout BinaryReader) throws {
            action = try reader.readUInt32()
            location = try reader.readUInt32()
            target = try reader.bytesRemaining >= 4 ? reader.readUInt32() : nil
            flags = try reader.bytesRemaining >= 4 ? reader.readUInt32() : nil
            timeMultipliers = try reader.bytesRemaining >= 12 ? reader.readFloat3() : nil
            maxTime = try reader.bytesRemaining >= 4 ? reader.readFloat32() : nil
            minTime = try reader.bytesRemaining >= 4 ? reader.readFloat32() : nil
            targetPercentBetweenActors = try reader.bytesRemaining >= 4 ? reader.readFloat32() : nil
            nearTargetDistance = try reader.bytesRemaining >= 4 ? reader.readFloat32() : nil
        }
    }

    public let formID: FormID
    public let editorID: String?
    public let model: ModelData?
    public let properties: Properties?
    public let dataSize: Int?
    /// MNAM, an IMAD.
    public let imageSpaceModifier: FormID?
    public let skipped: FieldTally

    public init(record: ESMRecord) throws {
        var fields = try RecordFields(record: record, type: "CAMS")
        formID = fields.formID
        editorID = fields.editorID()
        model = fields.model()
        dataSize = fields.fields.first { $0.type == "DATA" }?.data.count
        properties = fields.read("DATA") { try Properties(&$0) }
        imageSpaceModifier = fields.formID("MNAM")
        skipped = fields.finish()
    }
}

nonisolated public struct CameraPath: Equatable, Sendable {
    public let formID: FormID
    public let editorID: String?
    public let conditions: [Condition]
    /// ANAM: the parent path and the previous sibling.
    public let parent: FormID?
    public let previousSibling: FormID?
    /// DATA: 0 default, 1 disable, 2 shot list; 0x80 set means the path needs no shots.
    public let zoom: UInt8?
    /// SNAM, CAMS records in order.
    public let shots: [FormID]
    public let skipped: FieldTally

    /// True when the zoom value says the path must have camera shots.
    public var requiresShots: Bool {
        (zoom ?? 0) & 0x80 == 0
    }

    public init(record: ESMRecord) throws {
        var fields = try RecordFields(record: record, type: "CPTH")
        formID = fields.formID
        editorID = fields.editorID()
        conditions = fields.conditions()
        let links = fields.read("ANAM") { reader in
            try (reader.readFormID().nonNull, reader.readFormID().nonNull)
        }
        parent = links?.0
        previousSibling = links?.1
        zoom = fields.uint8("DATA")
        shots = fields.formIDs("SNAM")
        skipped = fields.finish()
    }
}
