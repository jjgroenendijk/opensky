public import OpenSkyAudio
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyPhysics

/// What `ActorGraphWorldAdapter` and its parts keep between frames.
public final class ActorGraphPartState {
    /// Each mover's drive gait, which picks its footstep list.
    public var gaits: [ReferenceKey: LocomotionGait] = [:]
    /// Each mover's ground material, which picks its footstep sound.
    public var groundMaterials: [ReferenceKey: FormID] = [:]
    /// The movers whose last drive moved them, for their movement loops.
    public var movers: Set<ReferenceKey> = []
    /// Each rolled actor base's sound types, after its audio template.
    public var actorSounds: [LeveledActorRollKey: ActorSounds] = [:]
    /// Each rolled actor base's race graph project and weight.
    public var graphBases: [LeveledActorRollKey: ActorGraphBase] = [:]

    public init() {}
}

/// `path` is nil when the race names no graph.
public struct ActorGraphBase {
    let path: String?
    let weight: Float
}
