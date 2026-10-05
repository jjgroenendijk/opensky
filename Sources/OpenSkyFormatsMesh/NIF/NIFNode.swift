// NiNode: a grouping node with child refs under a local transform. Subclasses
// such as BSFadeNode only append fields, so one decoder reads the shared
// prefix. Layout: docs/formats/nif.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct NIFNode: Sendable {
    /// Block types traversed as plain grouping nodes: NiNode layout prefix,
    /// draw-all-children semantics. Selector nodes (NiSwitchNode, NiLODNode)
    /// are absent: drawing every child would stack their alternatives.
    public static let traversedTypes: Set = [
        "NiNode", "BSFadeNode", "BSLeafAnimNode", "BSTreeNode",
        "BSOrderedNode", "BSMultiBoundNode"
    ]

    public let object: NIFObjectPrefix
    /// Child block refs in file order; -1 = empty slot (kept positional).
    public let children: [Int32]

    public init(object: NIFObjectPrefix, children: [Int32]) {
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
