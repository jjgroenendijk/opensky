// A door whose mesh moves its leaves with `Open` and `Close` controller sequences
// instead of a behaviour graph. Each leaf node is a root bone at its model-frame
// transform, as a cart wheel is. See docs/engine/object-animation.md#sequence-doors.

import Foundation
import OpenSkyBehavior
import OpenSkyFormatsAnimation
import OpenSkyFormatsMesh
import simd

nonisolated public struct SequenceDoorRig: Sendable {
    public enum Motion: Sendable {
        case open
        case close
    }

    /// One root bone per leaf, at the leaf's rest transform in the model frame.
    public let skeleton: HKASkeleton
    public let open: NIFSequence
    public let close: NIFSequence
    /// Each leaf's parent node in the model frame. A sequence key is relative to it.
    let parents: [float4x4]
    /// Each leaf's rest transform relative to its parent, for parts a track leaves unset.
    let restLocals: [HKABonePose]
    /// Each leaf's rest transform in the model frame.
    let rests: [float4x4]
    let openChannels: [NIFTransformChannel?]
    let closeChannels: [NIFTransformChannel?]
    /// Node block to the leaf it moves with: itself or its nearest leaf ancestor.
    let leafOfBlock: [Int: Int]

    /// Nil for a mesh without both sequences or without a node they move.
    public init?(file: NIFFile) throws {
        let sequences = try file.sequences()
        func named(_ name: String) -> NIFSequence? {
            sequences.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        }
        guard let open = named("Open"), let close = named("Close") else { return nil }
        let hierarchy = try NIFNodeHierarchy(file: file)
        let parentOf = file.nodeParents()
        var blockOf: [String: Int] = [:]
        for (block, name) in hierarchy.names.sorted(by: { $0.key < $1.key })
            where blockOf[name] == nil
        {
            blockOf[name] = block
        }
        var leaves: [(name: String, block: Int)] = []
        for name in Self.movedNodes(open) + Self.movedNodes(close)
            where !leaves.contains(where: { $0.name == name })
        {
            if let block = blockOf[name], hierarchy.worldTransforms[block] != nil {
                leaves.append((name, block))
            }
        }
        guard !leaves.isEmpty else { return nil }
        let rests = leaves.map { hierarchy.worldTransforms[$0.block] ?? matrix_identity_float4x4 }
        let parents = leaves.map { leaf in
            parentOf[leaf.block].flatMap { hierarchy.worldTransforms[$0] }
                ?? matrix_identity_float4x4
        }
        self.open = open
        self.close = close
        self.rests = rests
        self.parents = parents
        restLocals = zip(parents, rests).map { HKABonePose(transform: $0.inverse * $1) }
        openChannels = leaves.map { Self.channel(of: $0.name, in: open) }
        closeChannels = leaves.map { Self.channel(of: $0.name, in: close) }
        skeleton = HKASkeleton(
            name: nil,
            bones: leaves.map { HKABone(name: $0.name, lockTranslation: false) },
            parentIndices: leaves.map { _ in -1 },
            referencePose: rests.map { HKABonePose(transform: $0) }
        )
        leafOfBlock = Self.leafOfBlock(
            leaves: leaves.map(\.block), blocks: hierarchy.names.keys, parentOf: parentOf
        )
    }

    public func sequence(_ motion: Motion) -> NIFSequence {
        motion == .open ? open : close
    }

    /// Each leaf in the model frame at `time`, a key time of `motion`'s sequence.
    public func leafTransforms(_ motion: Motion, at time: Float) -> [float4x4] {
        let channels = motion == .open ? openChannels : closeChannels
        return rests.indices.map { index in
            guard let channel = channels[index] else { return rests[index] }
            let rest = restLocals[index]
            let local = HKABonePose(
                translation: channel.translation(at: time) ?? rest.translation,
                rotation: channel.rotation(at: time) ?? rest.rotation,
                scale: channel.scale(at: time).map { SIMD3(repeating: $0) } ?? rest.scale
            )
            return parents[index] * SkeletonPoseMath.localMatrix(local)
        }
    }

    /// Each leaf's move from its rest transform, in the model frame.
    public func leafDeltas(_ transforms: [float4x4]) -> [float4x4] {
        zip(transforms, rests).map { $0 * $1.inverse }
    }

    /// The leaf a node block moves with, or nil for a block that stays still.
    public func leaf(ofBlock block: Int) -> Int? {
        leafOfBlock[block]
    }

    private static func movedNodes(_ sequence: NIFSequence) -> [String] {
        sequence.tracks.compactMap { track in
            guard case let .node(name) = track.target, case .transform = track.channel
            else { return nil }
            return name
        }
    }

    private static func channel(of node: String, in sequence: NIFSequence) -> NIFTransformChannel? {
        sequence.tracks.lazy.compactMap { track -> NIFTransformChannel? in
            guard
                case let .node(name) = track.target, name == node,
                case let .transform(channel) = track.channel
            else { return nil }
            return channel
        }.first
    }

    private static func leafOfBlock(
        leaves: [Int], blocks: some Sequence<Int>, parentOf: [Int: Int]
    ) -> [Int: Int] {
        var result: [Int: Int] = [:]
        for block in blocks {
            var current: Int? = block
            var steps = 0
            while let node = current, steps < 64 {
                if let leaf = leaves.firstIndex(of: node) {
                    result[block] = leaf
                    break
                }
                current = parentOf[node]
                steps += 1
            }
        }
        return result
    }
}
