// BPTD body part data: the hit, sever, and explode parts of a creature's
// skeleton. Each part is a run that starts at BPTN (or at BPNN when the name
// is missing). Layout and sources: docs/formats/body-parts.md.

import Foundation
import OpenSkyFormatsCore

/// BPND, 84 bytes.
nonisolated public struct BodyPartNodeData: Equatable, Sendable {
    public let damageMultiplier: Float
    /// 0x01 severable, 0x02 IK data, 0x04 IK biped data, 0x08 explodable,
    /// 0x10 IK is head, 0x20 IK headtracking, 0x40 absolute to-hit chance.
    public let flags: UInt8
    /// 0 torso, 1 head, 2 eye, 3 look-at, 4 fly grab, 5 saddle.
    public let partType: UInt8
    public let healthPercent: UInt8
    /// An actor-value index, -1 for none.
    public let actorValue: Int8
    public let toHitChance: UInt8
    public let explosionChance: UInt8
    public let explodableDebrisCount: UInt16
    public let explodableDebris: FormID?
    public let explodableExplosion: FormID?
    public let trackingMaxAngle: Float
    public let explodableDebrisScale: Float
    public let severableDebrisCount: Int32
    public let severableDebris: FormID?
    public let severableExplosion: FormID?
    public let severableDebrisScale: Float
    public let goreOffset: SIMD3<Float>
    public let goreRotation: SIMD3<Float>
    public let severableImpactDataSet: FormID?
    public let explodableImpactDataSet: FormID?
    public let severableDecalCount: UInt8
    public let explodableDecalCount: UInt8
    /// Two bytes xEdit leaves unnamed.
    public let unknown: UInt16
    public let limbReplacementScale: Float

    init(_ reader: inout BinaryReader) throws {
        damageMultiplier = try reader.readFloat32()
        flags = try reader.readUInt8()
        partType = try reader.readUInt8()
        healthPercent = try reader.readUInt8()
        actorValue = try reader.readInt8()
        toHitChance = try reader.readUInt8()
        explosionChance = try reader.readUInt8()
        explodableDebrisCount = try reader.readUInt16()
        explodableDebris = try reader.readFormID().nonNull
        explodableExplosion = try reader.readFormID().nonNull
        trackingMaxAngle = try reader.readFloat32()
        explodableDebrisScale = try reader.readFloat32()
        severableDebrisCount = try reader.readInt32()
        severableDebris = try reader.readFormID().nonNull
        severableExplosion = try reader.readFormID().nonNull
        severableDebrisScale = try reader.readFloat32()
        goreOffset = try reader.readFloat3()
        goreRotation = try reader.readFloat3()
        severableImpactDataSet = try reader.readFormID().nonNull
        explodableImpactDataSet = try reader.readFormID().nonNull
        severableDecalCount = try reader.readUInt8()
        explodableDecalCount = try reader.readUInt8()
        unknown = try reader.readUInt16()
        limbReplacementScale = try reader.readFloat32()
    }
}

nonisolated public struct BodyPart: Equatable, Sendable {
    /// BPTN, the display name.
    public var name: LString?
    /// PNAM, the pose-matching node.
    public var poseMatching: String?
    /// BPNN, the skeleton node this part sits on.
    public var nodeName: String?
    /// BPNT, the VATS target node.
    public var vatsTarget: String?
    /// BPNI, the IK start node.
    public var ikStartNode: String?
    public var nodeData: BodyPartNodeData?
    /// NAM1, the limb that replaces the severed part.
    public var limbReplacementModel: String?
    /// NAM4, the bone the gore effects attach to.
    public var goreTargetBone: String?
    /// NAM5 texture hashes, kept raw.
    public var goreTextureHashes: Data?
}

nonisolated public struct BodyPartData: Equatable, Sendable {
    public let formID: FormID
    public let editorID: String?
    public let model: ModelData?
    public let parts: [BodyPart]
    public let skipped: FieldTally

    public init(record: ESMRecord, localized: Bool) throws {
        var fields = try RecordFields(record: record, type: "BPTD", localized: localized)
        formID = fields.formID
        editorID = fields.editorID()
        model = fields.model()
        parts = Self.parts(&fields)
        skipped = fields.finish()
    }

    /// The part on a skeleton node, compared without case.
    public func part(onNode node: String) -> BodyPart? {
        parts.first { $0.nodeName?.caseInsensitiveCompare(node) == .orderedSame }
    }

    private static func parts(_ fields: inout RecordFields) -> [BodyPart] {
        var parts: [BodyPart] = []
        for index in fields.fields.indices where !fields.isUsed(at: index) {
            let type = fields.fields[index].type
            guard partFields.contains(type) else { continue }
            let opensPart = type == "BPTN" || (type == "BPNN" && parts.last?.nodeName != nil)
            if opensPart || parts.isEmpty {
                parts.append(BodyPart())
            }
            assign(at: index, to: &parts[parts.count - 1], from: &fields)
        }
        return parts
    }

    private static func assign(
        at index: Int,
        to part: inout BodyPart,
        from fields: inout RecordFields
    ) {
        let field = fields.fields[index]
        let localized = fields.localized
        switch field.type {
        case "BPTN":
            part.name = fields
                .read(at: index) { _ in try LString(field: field, localized: localized) }
        case "PNAM": part.poseMatching = fields.read(at: index) { try $0.readZString() }
        case "BPNN": part.nodeName = fields.read(at: index) { try $0.readZString() }
        case "BPNT": part.vatsTarget = fields.read(at: index) { try $0.readZString() }
        case "BPNI": part.ikStartNode = fields.read(at: index) { try $0.readZString() }
        case "BPND": part.nodeData = fields.read(at: index) { try BodyPartNodeData(&$0) }
        case "NAM1": part.limbReplacementModel = fields.read(at: index) { try $0.readZString() }
        case "NAM4": part.goreTargetBone = fields.read(at: index) { try $0.readZString() }
        default:
            part.goreTextureHashes = fields
                .read(at: index) { try $0.read(count: $0.bytesRemaining) }
        }
    }

    private static let partFields: Set<FourCC> = [
        "BPTN", "PNAM", "BPNN", "BPNT", "BPNI", "BPND", "NAM1", "NAM4", "NAM5"
    ]
}
