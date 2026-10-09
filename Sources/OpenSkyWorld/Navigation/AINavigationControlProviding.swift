// The AI panel's seam: the selected actor, its mover and its scheduled package. The
// panel cannot reach `CellStreamer` or the fixed-step runtimes, so it cannot drive them.
// One snapshot, so sections agree. An explicit selection follows one named actor
// through a crowd, unlike Combat & Physics' nearest actor.

import OpenSkyFormatsESM
import simd

/// One resident actor as the gate panel's selector offers it.
nonisolated public struct AIActorOption: Equatable, Sendable {
    public let key: ReferenceKey
    /// The same display name `CombatLoopReadout` prints, so the two panels
    /// cannot disagree about what an actor is called.
    public let name: String
    /// Distance from the camera, world units, which is what makes a popup of a
    /// dozen identical guards navigable.
    public let distance: Float
    /// True when the world state records this actor dead. A corpse still
    /// appears in the list: selecting one and seeing every section say so is
    /// how a user finds out why nothing is moving.
    public let isDead: Bool

    public init(key: ReferenceKey, name: String, distance: Float, isDead: Bool) {
        self.key = key
        self.name = name
        self.distance = distance
        self.isDead = isDead
    }
}

/// One observation of everything the gate panel's non-combat sections show.
nonisolated public struct AINavigationSnapshot: Equatable, Sendable {
    /// False when no cell is streamed — no game data, or a synthetic scene.
    /// Every other field is then empty and the panel says so rather than
    /// showing a convincing zero.
    public let isAvailable: Bool
    /// Every resident actor, nearest first.
    public let actors: [AIActorOption]
    /// The actor every section acts on, or nil when none is resident.
    public let selectedActor: ReferenceKey?
    public let selectedActorName: String
    /// The selected actor's mover, or nil when it is standing still.
    public let movement: NPCMovementReadout?
    /// Movers running right now, across every actor, against the runtime cap.
    public let moverCount: Int
    public let moverLimit: Int
    /// The selected actor's package selection, or nil when the runtime has not
    /// registered it.
    public let package: PackageActorReadout?
    /// Actors the package runtime has registered, which is how many of the
    /// residents above are keeping a schedule at all.
    public let packagedActorCount: Int
    /// Where the crosshair is pointing, world space, or nil when it is not on
    /// anything. This is what the move control paths to.
    public let crosshairPoint: SIMD3<Float>?
    /// Whether the selected actor regards the player as an enemy. Where it is
    /// in a fight comes from `CombatLoopSnapshot.actors`, which already carries
    /// one line per actor with a behavior machine; duplicating the phase here
    /// would give the same question two answers taken a tick apart.
    public let selectedActorIsHostile: Bool
    /// Human-readable result of the last panel action.
    public let lastActionText: String
    /// The selected actor's procedure machine, when a scene or alias package holds it.
    public var procedure: PackageProcedureMachine?
    /// What the selected actor rides, such as a cart, or nil.
    public var carrier: ReferenceKey?

    /// The reading with no streamed cell attached.
    public static let unavailable = AINavigationSnapshot(
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

    public init(
        isAvailable: Bool,
        actors: [AIActorOption],
        selectedActor: ReferenceKey?,
        selectedActorName: String,
        movement: NPCMovementReadout?,
        moverCount: Int,
        moverLimit: Int,
        package: PackageActorReadout?,
        packagedActorCount: Int,
        crosshairPoint: SIMD3<Float>?,
        selectedActorIsHostile: Bool,
        lastActionText: String
    ) {
        self.isAvailable = isAvailable
        self.actors = actors
        self.selectedActor = selectedActor
        self.selectedActorName = selectedActorName
        self.movement = movement
        self.moverCount = moverCount
        self.moverLimit = moverLimit
        self.package = package
        self.packagedActorCount = packagedActorCount
        self.crosshairPoint = crosshairPoint
        self.selectedActorIsHostile = selectedActorIsHostile
        self.lastActionText = lastActionText
    }
}

@MainActor
public protocol AINavigationControlProviding: AnyObject {
    var aiNavigationSnapshot: AINavigationSnapshot { get }

    /// The actor the whole destination acts on. Setting nil returns the panel
    /// to following the nearest resident actor, which is what it does before a
    /// user has chosen anything.
    var selectedAIActor: ReferenceKey? { get set }

    /// Whether the selected actor regards the player as an enemy. Unlike
    /// `CombatLoopControlProviding.selectedActorIsHostile`, this follows the explicit
    /// selection, not the nearest actor.
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
