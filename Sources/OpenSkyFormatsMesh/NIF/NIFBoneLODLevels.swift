// Bone levels of detail: `BSBoneLODExtraData` names bones with camera distances, and
// `NiBSBoneLODController` groups nodes per level. Layout: docs/formats/nif-extra-data.md.

import Foundation

nonisolated public struct NIFBoneLODLevels: Equatable, Sendable {
    /// One `BSBoneLODExtraData` entry with its node resolved.
    public struct Bone: Equatable, Sendable {
        public let distance: Float
        /// Index into `NIFNodeAnimation.nodes`; nil when no node has the name.
        public let node: Int?
        public let name: String?

        public init(distance: Float, node: Int?, name: String?) {
            self.distance = distance
            self.node = node
            self.name = name
        }
    }

    /// `NiBSBoneLODController` node groups, one per level.
    public let levels: [[Int]]
    public let bones: [Bone]

    public init(levels: [[Int]], bones: [Bone]) {
        self.levels = levels
        self.bones = bones
    }

    /// The nodes that stop animating with the camera `distance` away: each named bone
    /// past its distance, and every node below it.
    public func frozenNodes(
        atDistance distance: Float,
        in animation: NIFNodeAnimation
    ) -> Set<Int> {
        let roots = Set(bones.filter { distance > $0.distance }.compactMap(\.node))
        guard !roots.isEmpty else { return [] }
        var frozen = Set<Int>()
        for node in animation.nodes.indices {
            var current: Int? = node
            var depth = 0
            while let index = current, depth < 64 {
                if roots.contains(index) {
                    frozen.insert(node)
                    break
                }
                current = animation.nodes[index].parent
                depth += 1
            }
        }
        return frozen
    }
}
