// A skeleton pose as world matrices in bone order, with the bone names held once
// per skeleton. Skinning maps its bones to skeleton indices once per skeleton, so a
// frame hashes no bone names.

public import simd

/// One skeleton's bone names and a name-to-index map, built once per skeleton.
/// A repeated name resolves to its first bone, the order skinning has always used.
nonisolated public final class SkeletonBoneIndex: Sendable {
    public let names: [String]
    private let firstIndexByName: [String: Int]

    public init(names: [String]) {
        self.names = names
        var indices: [String: Int] = [:]
        indices.reserveCapacity(names.count)
        for (index, name) in names.enumerated() where indices[name] == nil {
            indices[name] = index
        }
        firstIndexByName = indices
    }

    public func index(of name: String) -> Int? {
        firstIndexByName[name]
    }
}

/// World matrices in `bones.names` order. A bone past the end of `matrices` is unposed.
nonisolated public struct SkeletonPose: Sendable {
    public let bones: SkeletonBoneIndex
    public private(set) var matrices: [float4x4]

    public init(bones: SkeletonBoneIndex, matrices: [float4x4]) {
        self.bones = bones
        self.matrices = matrices
    }

    /// The pose keyed by bone name, for a caller outside the per-frame path.
    public var named: [String: float4x4] {
        var named: [String: float4x4] = [:]
        for (name, matrix) in zip(bones.names, matrices) where named[name] == nil {
            named[name] = matrix
        }
        return named
    }

    /// The pose with some bones replaced by name, such as a ragdoll's simulated bones.
    /// Every other bone moves with its nearest replaced ancestor in `parents`, so a
    /// finger follows its ragdoll hand. A name this skeleton does not pose is ignored.
    public func overriding(_ replacements: [String: float4x4], parents: [Int]) -> SkeletonPose {
        var pose = self
        var moved = [Bool](repeating: false, count: matrices.count)
        for (name, matrix) in replacements {
            guard let index = bones.index(of: name), index < matrices.count else { continue }
            pose.matrices[index] = matrix
            moved[index] = true
        }
        guard parents.count == matrices.count else { return pose }
        pose.carryChildren(of: moved, from: matrices, parents: parents)
        return pose
    }

    /// Moves each bone that was not replaced by its parent's move, parents first.
    /// Repeats over the bones until none changes, so any bone order works.
    private mutating func carryChildren(
        of replaced: [Bool], from original: [float4x4], parents: [Int]
    ) {
        var settled = replaced
        var moved = replaced
        var progress = true
        while progress {
            progress = false
            for index in matrices.indices where !settled[index] {
                let parent = parents[index]
                guard matrices.indices.contains(parent) else {
                    settled[index] = true
                    progress = true
                    continue
                }
                guard settled[parent] else { continue }
                if moved[parent] {
                    matrices[index] = matrices[parent] * original[parent].inverse
                        * original[index]
                    moved[index] = true
                }
                settled[index] = true
                progress = true
            }
        }
    }
}
