// The mesh nodes a rig's bones move, so the collision bodies under them move with the
// pose. See docs/engine/object-animation.md#moving-collision.

public import OpenSkyFormatsMesh
public import simd

nonisolated public struct MovingPartRig: Sendable {
    /// Each bone's node in the model frame at rest. Nil for a bone the mesh has no node for.
    public let rests: [float4x4?]
    /// Node block to the bone it moves with: its own or its nearest moved ancestor's.
    let partOfBlock: [Int: Int]

    /// Nil when no bone names a node of the mesh.
    public init?(file: NIFFile, boneNames: [String]) throws {
        let hierarchy = try NIFNodeHierarchy(file: file)
        var blockOf: [String: Int] = [:]
        for (block, name) in hierarchy.names.sorted(by: { $0.key < $1.key })
            where blockOf[name.lowercased()] == nil && hierarchy.worldTransforms[block] != nil
        {
            blockOf[name.lowercased()] = block
        }
        let blocks = boneNames.map { blockOf[$0.lowercased()] }
        guard blocks.contains(where: { $0 != nil }) else { return nil }
        rests = blocks.map { $0.flatMap { hierarchy.worldTransforms[$0] } }
        partOfBlock = Self.partOfBlock(
            parts: blocks, blocks: hierarchy.names.keys, parentOf: file.nodeParents()
        )
    }

    public func part(ofBlock block: Int) -> Int? {
        partOfBlock[block]
    }

    /// Each bone's move from rest in the model frame, from its posed model-frame transform.
    /// Nil when `posed` does not hold one transform per bone.
    public func deltas(posed: [float4x4]) -> [float4x4]? {
        guard posed.count == rests.count else { return nil }
        return zip(posed, rests).map { pose, rest in
            rest.map { pose * $0.inverse } ?? matrix_identity_float4x4
        }
    }

    static func partOfBlock(
        parts: [Int?], blocks: some Sequence<Int>, parentOf: [Int: Int]
    ) -> [Int: Int] {
        var result: [Int: Int] = [:]
        for block in blocks {
            var current: Int? = block
            var steps = 0
            while let node = current, steps < 64 {
                if let part = parts.firstIndex(of: node) {
                    result[block] = part
                    break
                }
                current = parentOf[node]
                steps += 1
            }
        }
        return result
    }
}
