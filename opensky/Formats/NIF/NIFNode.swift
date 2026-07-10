// NiNode: scene-graph grouping node — child block refs under a local
// transform. BSFadeNode and friends inherit NiNode in nif.xml and only
// append fields, so one decoder reads the shared prefix; appended tails and
// the effects list stay unread inside the size-sliced block payload.
//
// Reference: NifTools nif.xml (NiNode; BSFadeNode, BSLeafAnimNode,
// BSTreeNode, BSOrderedNode, BSMultiBoundNode inherit it).
//   https://github.com/niftools/nifxml/blob/develop/nif.xml
// Layout documented in docs/formats/nif.md.

import Foundation

nonisolated struct NIFNode {
    /// Block types traversed as plain grouping nodes: NiNode layout prefix,
    /// draw-all-children semantics. Selector nodes (NiSwitchNode, NiLODNode)
    /// are deliberately absent — drawing every child would stack their
    /// alternatives on top of each other.
    static let traversedTypes: Set = [
        "NiNode", "BSFadeNode", "BSLeafAnimNode", "BSTreeNode",
        "BSOrderedNode", "BSMultiBoundNode"
    ]

    let object: NIFObjectPrefix
    /// Child block refs in file order; -1 = empty slot (kept positional).
    let children: [Int32]

    init(data: Data, header: NIFHeader) throws {
        var reader = BinaryReader(data)
        object = try NIFObjectPrefix(reader: &reader, header: header)

        let childCount = try Int(reader.readUInt32())
        guard childCount * 4 <= reader.bytesRemaining else {
            throw NIFError.malformed("child count \(childCount) exceeds block size")
        }
        var children: [Int32] = []
        children.reserveCapacity(childCount)
        for _ in 0 ..< childCount {
            try children.append(Int32(bitPattern: reader.readUInt32()))
        }
        self.children = children
        // Effects list + subclass tail fields ignored; the block slice
        // bounds them.
    }
}
