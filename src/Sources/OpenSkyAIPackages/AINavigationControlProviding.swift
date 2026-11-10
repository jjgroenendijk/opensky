// The AI readout's seam: the selected actor, its mover and its scheduled package. The
// readout cannot reach `CellStreamer` or the fixed-step runtimes, so it cannot drive them.
// One snapshot, so sections agree. An explicit selection follows one named actor
// through a crowd, unlike Combat & Physics' nearest actor.

public import OpenSkyFormatsESM
import simd

/// One resident actor as the gate readout's selector offers it.
nonisolated struct AIActorOption: Equatable, Sendable {
    let key: ReferenceKey
    /// The same display name `CombatLoopReadout` prints, so the two readouts
    /// cannot disagree about what an actor is called.
    let name: String
    /// Distance from the camera, world units, which is what makes a popup of a
    /// dozen identical guards navigable.
    let distance: Float
}

/// One observation of everything the gate readout's non-combat sections show.
nonisolated struct AINavigationSnapshot: Equatable, Sendable {
    /// Every resident actor, nearest first.
    let actors: [AIActorOption]
    /// The actor every section acts on, or nil when none is resident.
    let selectedActor: ReferenceKey?
    /// Where the crosshair is pointing, world space, or nil when it is not on
    /// anything. This is what the move control paths to.
    let crosshairPoint: SIMD3<Float>?
    /// Whether the selected actor regards the player as an enemy. Where it is
    /// in a fight comes from `CombatLoopSnapshot.actors`, which already carries
    /// one line per actor with a behavior machine; duplicating the phase here
    /// would give the same question two answers taken a tick apart.
    let selectedActorIsHostile: Bool

    /// The reading with no streamed cell attached.
    static let unavailable = AINavigationSnapshot(
        actors: [],
        selectedActor: nil,
        crosshairPoint: nil,
        selectedActorIsHostile: false
    )
}
