// The state a graph instance keeps for each node family, grouped so each family
// reads its own memory.

public import OpenSkyFormatsAnimation

nonisolated extension BehaviorGraphInstance {
    /// What the state machines remember between updates.
    struct MachineMemory {
        /// Per-state-machine runtime state. Not cleared by `deactivate()`:
        /// `m_startStateMode` 2 re-enters the state that was current when it stopped.
        var machineStates: [HKXPointerTarget: BehaviorMachineState] = [:]
        /// Parsed transition conditions, keyed by the condition object. The
        /// optional is stored so a string that will not parse is parsed once.
        var conditionCache: [HKXPointerTarget: BehaviorConditionExpression?] = [:]
        /// Global wildcard routes per machine, built on first reach.
        var globalWildcardRouteCache: [HKXPointerTarget: [BehaviorGlobalWildcardRoute]] = [:]
        /// The state machines' own random source, for random start states and transitions.
        var stateMachineRandom = BehaviorStateMachineRandom()
    }

    /// The ragdoll and character hand-offs between the graph and physics.
    public struct PhysicsOutputs {
        /// Seconds the animated-to-simulated blend takes, from the last evaluated
        /// `hkbRigidBodyRagdollControlsModifier`. Nil until one has run.
        public var ragdollBlendDuration: Float?
        /// The `hkbPoweredRagdollControlsModifier` the last update ran, or nil.
        public var poweredRagdollControls: HKBPoweredRagdollControlsModifier?
        /// The event the last update's `BSRagdollContactListenerModifier` raises on contact.
        public var ragdollContactEvent: String?
        /// Where the character stands and what ground it stands on.
        public var characterContext = BehaviorCharacterContext()
        /// The physics hand-offs the last update's modifiers asked for.
        public var physicsRequests = BehaviorPhysicsRequests()

        public init() {}
    }

    /// What clips, blenders, and modifiers remember between updates.
    struct NodeMemory {
        /// Parsed `hkbEvaluateExpressionModifier` statements per expression array.
        var statementCache: [HKXPointerTarget: [BehaviorExpressionStatement?]] = [:]
        /// Mean ankle correction of the last foot IK solve, model space.
        var footIkError = SIMD3<Float>()
        /// The pose each cyclic blend generator produced last, so a crossfade can start from it.
        var cyclicLastPoses: [HKXPointerTarget: BehaviorPose] = [:]
        /// The held blender each cyclic blend fades away from, which keeps running.
        var cyclicCopies: [HKXPointerTarget: BehaviorCyclicCopy] = [:]
        /// True while a synced blender runs a follower, whose annotations repeat the leader's.
        var mutesClipAnnotations = false
        /// The blend parameter a cyclic blend generator hands its blender, by blender.
        var blendParameterOverrides: [HKXPointerTarget: Float] = [:]
        /// The source of every random choice the graph makes. Seeded the same for
        /// every instance, so two runs with the same input stay identical.
        var random = BehaviorRandom()
        /// This actor's views of the paired clips it played, by prefix and clip name.
        var pairedClips: [String: PairedBehaviorClip] = [:]
        /// The sync prefix of the synchronized clip being evaluated, nil outside one.
        var syncTrackPrefix: String?
    }
}
