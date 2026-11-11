// `NiNode` subclasses that append fields: add-on nodes (`BSValueNode`), range
// nodes for destruction stages, and master particle systems. Each draws its
// children like a plain node. Layout: docs/formats/nif.md#node-subclasses.

public import Foundation
public import OpenSkyFormatsCore
public import simd

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

    let node: NIFNode
    let min: UInt8
    let max: UInt8
    let current: UInt8

    init(reader: inout BinaryReader, header: NIFHeader) throws {
        node = try NIFNode(reader: &reader, header: header)
        min = try reader.readUInt8()
        max = try reader.readUInt8()
        current = try reader.readUInt8()
    }

    func contains(stage: Int) -> Bool {
        Int(min) ... Swift.max(Int(min), Int(max)) ~= stage
    }
}

/// `BSMasterParticleSystem`: a node whose particle systems share one emitter cap.
nonisolated public struct NIFMasterParticleSystem: Sendable {
    public static let typeName = "BSMasterParticleSystem"

    let node: NIFNode
    let maxEmitterObjects: UInt16
    let particleSystemRefs: [Int32]

    init(reader: inout BinaryReader, header: NIFHeader) throws {
        node = try NIFNode(reader: &reader, header: header)
        maxEmitterObjects = try reader.readUInt16()
        particleSystemRefs = try reader.readNIFRefs(label: "particle system")
    }
}

nonisolated extension NIFBlockDecoders {
    enum Nodes {
        static let nodes: [String: Decode] = [
            NIFValueNode.typeName: { try NIFValueNode(reader: &$0, header: $1) },
            NIFRangeNode.blastType: { try NIFRangeNode(reader: &$0, header: $1) },
            NIFRangeNode.damageStageType: { try NIFRangeNode(reader: &$0, header: $1) },
            NIFMasterParticleSystem
                .typeName: { try NIFMasterParticleSystem(reader: &$0, header: $1) }
        ]
    }
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
            var stack = NIFGraphStack(root: root, parent: walkParent(ofRoot: root))
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

// NiNode: a grouping node with child refs under a local transform. Subclasses
// such as BSFadeNode only append fields, so one decoder reads the shared prefix.

nonisolated public struct NIFNode: Sendable {
    /// Block types traversed as plain grouping nodes: NiNode layout prefix,
    /// draw-all-children semantics. Selector nodes (NiSwitchNode, NiLODNode)
    /// are absent: drawing every child would stack their alternatives. A billboard
    /// draws at rest unless a node rig turns it to the camera.
    public static let traversedTypes: Set = [
        "NiNode", "BSFadeNode", "BSLeafAnimNode", "BSTreeNode",
        "BSOrderedNode", "BSMultiBoundNode", NIFValueNode.typeName,
        NIFRangeNode.blastType, NIFRangeNode.damageStageType, NIFMasterParticleSystem.typeName,
        NIFBillboard.typeName
    ]

    public let object: NIFObjectPrefix
    /// Child block refs in file order; -1 = empty slot (kept positional).
    public let children: [Int32]

    init(object: NIFObjectPrefix, children: [Int32]) {
        self.object = object
        self.children = children
    }

    public init(data: Data, header: NIFHeader) throws {
        var reader = BinaryReader(data)
        object = try NIFObjectPrefix(reader: &reader, header: header)

        children = try Self.readRefs(&reader, label: "child")
        // Effects list + subclass tail fields ignored; the block slice
        // bounds them.
    }

    /// Reads the whole `NiNode` part, effects list included, so a subclass can
    /// continue with its own fields.
    public init(reader: inout BinaryReader, header: NIFHeader) throws {
        object = try NIFObjectPrefix(reader: &reader, header: header)
        children = try Self.readRefs(&reader, label: "child")
        _ = try Self.readRefs(&reader, label: "effect")
    }

    /// A uint32 count, then that many int32 block refs.
    static func readRefs(
        _ reader: inout BinaryReader,
        label: String
    ) throws -> [Int32] {
        let count = try Int(reader.readUInt32())
        guard count <= reader.bytesRemaining / 4 else {
            throw NIFError.malformed("\(label) count \(count) exceeds block size")
        }
        var refs: [Int32] = []
        refs.reserveCapacity(count)
        for _ in 0 ..< count {
            try refs.append(Int32(bitPattern: reader.readUInt32()))
        }
        return refs
    }
}
