// What a sub-graph is attached to, and what it reads from its actor. The game treats the
// graphs of the art objects and armour addons on an actor as the actor's sub-graphs
// (docs/engine/effect-graphs.md).

import OpenSkyActorPresentation
import OpenSkyBehavior
import OpenSkyFormatsESM
import simd

/// Which model a running sub-graph belongs to. Graphs step in this order.
nonisolated public enum SubGraphID: Hashable, Comparable, Sendable {
    /// A visual effect, by its instance id.
    case effect(Int)
    /// An armour addon model an actor wears, by the addon's form ID.
    case armorAddon(ReferenceKey, armature: UInt32)
}

nonisolated public enum SubGraphAnchor: Equatable, Sendable {
    case actor(ReferenceKey)
    /// An effect at a point, such as an explosion. No actor's events reach it.
    case point(SIMD3<Float>)
}

/// One live model whose graph may run as a sub-graph.
nonisolated public struct AttachedSubGraph: Equatable, Sendable {
    public let id: SubGraphID
    public let anchor: SubGraphAnchor
    public let name: String
    public let modelPath: String

    public init(id: SubGraphID, anchor: SubGraphAnchor, name: String, modelPath: String) {
        self.id = id
        self.anchor = anchor
        self.name = name
        self.modelPath = modelPath
    }

    public var actor: ReferenceKey? {
        guard case let .actor(key) = anchor else { return nil }
        return key
    }
}

/// The actor a sub-graph runs on, as the graph reads it before each step.
public struct SubGraphCharacter {
    public let context: BehaviorCharacterContext
    /// The actor's own graph variables; nil when the actor runs no graph.
    public let variables: BehaviorVariableStore?
    /// The rig and pose buffer an armour addon's graph moves; nil when no graph poses it.
    public let rig: SubGraphActorRig?

    public init(
        context: BehaviorCharacterContext,
        variables: BehaviorVariableStore?,
        rig: SubGraphActorRig? = nil
    ) {
        self.context = context
        self.variables = variables
        self.rig = rig
    }
}

/// The actor's skeleton and the buffer its own graph publishes its pose to.
public struct SubGraphActorRig {
    public let skeleton: BehaviorSkeleton
    public let pose: PlayerPoseBuffer

    public init(skeleton: BehaviorSkeleton, pose: PlayerPoseBuffer) {
        self.skeleton = skeleton
        self.pose = pose
    }
}
