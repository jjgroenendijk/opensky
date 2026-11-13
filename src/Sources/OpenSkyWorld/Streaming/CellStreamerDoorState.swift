// Door, trigger, and actor prop state of the resident cells.

import OpenSkyAudio
import OpenSkyCells
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyTerrain
public import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// Door, trigger, and actor prop state of the resident cells.
public final class CellStreamerDoorState {
    /// Source door of the transition that produced the current interior, so a
    /// mutation inside it can be rebuilt through the door-transition path.
    public var interiorSourceDoor: FormID?
    public internal(set) var doorTransitionFailureCount = 0
    /// Source placement retained across an asynchronous door build. Runtime
    /// state rebuilds have no player interaction and leave this nil.
    public var doorMotionInteraction: PlacedInteraction?
    /// Trigger volumes the player capsule was inside as of the last walk-mode
    /// frame, keyed by the authoring REFR. The per-frame diff against this set
    /// is what makes enter and leave edge events.
    public var occupiedTriggers: Set<ReferenceKey> = []
    /// Feet position of the previous walk-mode trigger test, so a frame that
    /// moved further than a capsule radius can be swept rather than sampled
    /// only at its destination. Nil outside walk mode.
    var lastTriggerFeetPosition: SIMD3<Float>?
    /// Automatic doors whose area held the player's feet last frame. Nil until the first
    /// frame in a scene, so arriving inside a door's area does not send the player back.
    public var automaticDoorOccupancy: Set<FormID>?
    /// Automatic door distances and the teleport delay; the app sets the install's values.
    public var doors = DoorSettings.vanilla
    /// Seconds a used load door still waits before its finished build is shown.
    var doorTransitionHold: Float = 0
    /// Finished door builds held back by `doorTransitionHold`.
    var heldDoorTransitions: [DoorTransitionBuildResult] = []
    /// Recent trigger edges, filled by a subscriber
    /// registered in `init`.
    public let triggerLog = TriggerEventLog()
    /// Idle props by actor, drawn outside the cell scenes (CellStreamerActorProps).
    public var actorProps: [FormID: ActorPropDraw] = [:]

    public init() {}
}
