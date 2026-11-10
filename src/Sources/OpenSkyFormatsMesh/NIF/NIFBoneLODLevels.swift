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
}
