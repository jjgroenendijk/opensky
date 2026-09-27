// Narrow provider seam for the M16 gate panel (issue #203, roadmap item 16.8):
// which actor the panel is talking about, where its mover is, and which package
// its schedule selected.
//
// The third seam of its kind, beside `AIOverlayControlProviding` (16.3) and
// `PerceptionControlProviding` (16.6), and written for the same reason: the
// panel must not be able to reach `CellStreamer`, `NPCMovementRuntime` or
// `ActorPackageRuntime`, because a panel that could reach a fixed-step runtime
// could also drive it between steps, and a readout taken that way stops
// describing the world it claims to describe.
//
// One snapshot rather than a bag of properties, for the reason
// `CombatLoopSnapshot` is one: five sections read this within a single 2 Hz
// tick, and five separate reads taken microseconds apart while an actor walks
// through a door would disagree with each other.
//
// The *selection* is the piece all six sections share. Combat & Physics selects
// the nearest resident actor implicitly and cannot say otherwise; that is fine
// for one opponent standing in front of you and useless for watching one named
// Whiterun guard keep a schedule while four others walk past. So the gate panel
// carries an explicit selection, and everything under it — the mover, the
// package, the detection pairs, the combat phase — answers for that actor.
//
// AppKit-free, so it compiles into `openskycli` beside the app.

import simd

/// One resident actor as the gate panel's selector offers it.
nonisolated struct AIActorOption: Equatable, Sendable {
    let key: ReferenceKey
    /// The same display name `CombatLoopReadout` prints, so the two panels
    /// cannot disagree about what an actor is called.
    let name: String
    /// Distance from the camera, world units, which is what makes a popup of a
    /// dozen identical guards navigable.
    let distance: Float
    /// True when the world state records this actor dead. A corpse still
    /// appears in the list: selecting one and seeing every section say so is
    /// how a user finds out why nothing is moving.
    let isDead: Bool
}

/// One observation of everything the gate panel's non-combat sections show.
nonisolated struct AINavigationSnapshot: Equatable, Sendable {
    /// False when no cell is streamed — no game data, or a synthetic scene.
    /// Every other field is then empty and the panel says so rather than
    /// showing a convincing zero.
    let isAvailable: Bool
    /// Every resident actor, nearest first.
    let actors: [AIActorOption]
    /// The actor every section acts on, or nil when none is resident.
    let selectedActor: ReferenceKey?
    let selectedActorName: String
    /// The selected actor's mover, or nil when it is standing still.
    let movement: NPCMovementReadout?
    /// Movers running right now, across every actor, against the runtime cap.
    let moverCount: Int
    let moverLimit: Int
    /// The selected actor's package selection, or nil when the runtime has not
    /// registered it.
    let package: PackageActorReadout?
    /// Actors the package runtime has registered, which is how many of the
    /// residents above are keeping a schedule at all.
    let packagedActorCount: Int
    /// Where the crosshair is pointing, world space, or nil when it is not on
    /// anything. This is what the move control paths to.
    let crosshairPoint: SIMD3<Float>?
    /// Whether the selected actor regards the player as an enemy. Where it is
    /// in a fight comes from `CombatLoopSnapshot.actors`, which already carries
    /// one line per actor with a behavior machine; duplicating the phase here
    /// would give the same question two answers taken a tick apart.
    let selectedActorIsHostile: Bool
    /// Human-readable result of the last panel action.
    let lastActionText: String

    /// The reading with no streamed cell attached.
    static let unavailable = AINavigationSnapshot(
        isAvailable: false,
        actors: [],
        selectedActor: nil,
        selectedActorName: "—",
        movement: nil,
        moverCount: 0,
        moverLimit: 0,
        package: nil,
        packagedActorCount: 0,
        crosshairPoint: nil,
        selectedActorIsHostile: false,
        lastActionText: "AI unavailable: no cell is streamed."
    )
}

@MainActor
protocol AINavigationControlProviding: AnyObject {
    var aiNavigationSnapshot: AINavigationSnapshot { get }

    /// The actor the whole destination acts on. Setting nil returns the panel
    /// to following the nearest resident actor, which is what it does before a
    /// user has chosen anything.
    var selectedAIActor: ReferenceKey? { get set }

    /// Whether the *selected* actor regards the player as an enemy.
    ///
    /// `CombatLoopControlProviding.selectedActorIsHostile` acts on the nearest
    /// resident actor and cannot be told otherwise, which is right for the one
    /// opponent standing in front of you under `World > Combat & Physics` and
    /// wrong here: this destination exists to follow one named actor through a
    /// crowd, and angering a different one because it happened to be closer is
    /// exactly the confusion an explicit selection removes.
    var selectedAIActorIsHostile: Bool { get set }

    /// Selects whatever actor the crosshair is on, reusing the same ray the
    /// HUD target readout draws from. No-op with a recorded reason when the
    /// crosshair is on a wall.
    func selectAIActorFromCrosshair()

    /// Paths the selected actor to the crosshair point through 16.4's mover.
    func moveSelectedAIActorToCrosshair()

    /// Stops the selected actor's mover where it stands.
    func stopSelectedAIActor()

    /// Re-runs 16.5's package selection for the selected actor immediately,
    /// rather than waiting out the reevaluation interval.
    func reevaluateSelectedAIActorPackage()
}
