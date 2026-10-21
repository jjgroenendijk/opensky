// `NiNode` subclasses that append fields: add-on nodes (`BSValueNode`), range
// nodes for destruction stages, and master particle systems. Each draws its
// children like a plain node. Layout: docs/formats/nif.md#node-subclasses.

import Foundation
import OpenSkyFormatsCore
import simd

/// `BSValueNode`: a place where the game copies in an `ADDN` model by its index.
nonisolated public struct NIFValueNode: Sendable {
    public static let typeName = "BSValueNode"

    public let node: NIFNode
    /// The `ADDN` record's `DATA` index.
    public let value: UInt32
    /// nif.xml `BSValueNodeFlags`: bit 0 billboard world Z, bit 1 use player adjust.
    public let flags: UInt8

    public init(reader: inout BinaryReader, header: NIFHeader) throws {
        node = try NIFNode(reader: &reader, header: header)
        value = try reader.readUInt32()
        flags = try reader.readUInt8()
    }

    public init(data: Data, header: NIFHeader) throws {
        var reader = BinaryReader(data)
        try self.init(reader: &reader, header: header)
    }
}

/// nif.xml `BSRangeNode`: children for the stages from `min` through `max`.
/// `BSDamageStage` nodes hold what a destructible shows at its damage stages.
nonisolated public struct NIFRangeNode: Sendable {
    public static let blastType = "BSBlastNode"
    public static let damageStageType = "BSDamageStage"

    public let node: NIFNode
    public let min: UInt8
    public let max: UInt8
    public let current: UInt8

    public init(reader: inout BinaryReader, header: NIFHeader) throws {
        node = try NIFNode(reader: &reader, header: header)
        min = try reader.readUInt8()
        max = try reader.readUInt8()
        current = try reader.readUInt8()
    }

    public func contains(stage: Int) -> Bool {
        Int(min) ... Swift.max(Int(min), Int(max)) ~= stage
    }
}

/// `BSMasterParticleSystem`: a node whose particle systems share one emitter cap.
nonisolated public struct NIFMasterParticleSystem: Sendable {
    public static let typeName = "BSMasterParticleSystem"

    public let node: NIFNode
    public let maxEmitterObjects: UInt16
    public let particleSystemRefs: [Int32]

    public init(reader: inout BinaryReader, header: NIFHeader) throws {
        node = try NIFNode(reader: &reader, header: header)
        maxEmitterObjects = try reader.readUInt16()
        particleSystemRefs = try reader.readNIFRefs(label: "particle system")
    }
}

nonisolated extension NIFBlockDecoders {
    static let nodes: [String: Decode] = [
        NIFValueNode.typeName: { try NIFValueNode(reader: &$0, header: $1) },
        NIFRangeNode.blastType: { try NIFRangeNode(reader: &$0, header: $1) },
        NIFRangeNode.damageStageType: { try NIFRangeNode(reader: &$0, header: $1) },
        NIFMasterParticleSystem.typeName: { try NIFMasterParticleSystem(reader: &$0, header: $1) }
    ]
}

/// One add-on node: the `ADDN` index and where it sits in the model.
nonisolated public struct NIFAddOnNode: Equatable, Sendable {
    public let name: String?
    public let index: UInt32
    public let transform: simd_float4x4
    public let flags: UInt8

    public init(name: String?, index: UInt32, transform: simd_float4x4, flags: UInt8) {
        self.name = name
        self.index = index
        self.transform = transform
        self.flags = flags
    }
}

nonisolated extension NIFFile {
    /// Every `BSValueNode` the model draws, in model space. A hidden subtree, such
    /// as a later damage stage, and the inactive children of a switch hold none.
    public func addOnNodes() throws -> [NIFAddOnNode] {
        var found: [NIFAddOnNode] = []
        for root in roots {
            var stack = NIFGraphStack(root: root)
            while let visit = stack.next() {
                guard
                    visit.ref >= 0, Int(visit.ref) < blocks.count,
                    visit.depth <= 64 else { continue }
                let index = Int(visit.ref)
                guard stack.enter(index) else { continue }
                let block = blocks[index]
                let node: NIFNode
                if block.typeName == NIFSwitchNode.typeName {
                    node = try NIFSwitchNode(data: block.data, header: header).activeNode
                } else if NIFNode.traversedTypes.contains(block.typeName) {
                    node = try NIFNode(data: block.data, header: header)
                } else {
                    continue
                }
                guard !node.object.isHidden else { continue }
                let world = visit.parent * node.object.localTransform
                if block.typeName == NIFValueNode.typeName {
                    let value = try NIFValueNode(data: block.data, header: header)
                    found.append(NIFAddOnNode(
                        name: node.object.name, index: value.value, transform: world,
                        flags: value.flags
                    ))
                }
                stack.push(children: node.children, parent: world, depth: visit.depth + 1)
            }
        }
        return found
    }
}
