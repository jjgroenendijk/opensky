// Part of the `GameSession` state, held in one object so the session port can name it.

import OpenSkyActorPresentation
import OpenSkyAudio
public import OpenSkyPhysics
public import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyWeather
import OpenSkyWorldInterface
public import simd

/// What moves the player besides the walk controller: ground, seat, mount, package walk, and carry.
public final class SessionMotion {
    /// Resident static collision broadphase, wired beside terrain by
    /// GameViewController. Empty in renderer-only paths. Walk mode, the
    /// cameras and precipitation all query it.
    public var collisionQuery: CapsuleWorldCollider.CandidateQuery?
    /// The velocity a heavy moving body gives the player's capsule at its feet.
    public var characterCarry: ((PlayerCapsule, SIMD3<Float>) -> SIMD3<Float>)?
    /// Current resident terrain lookup, wired by GameViewController. nil in
    /// renderer-only tests/offscreen paths -> walk mode has no ground.
    public var terrainSampler: WalkController.GroundSampler?
    /// Whether the player may walk from one point to the next: the border regions.
    public var borderCheck: (@Sendable (SIMD2<Float>, SIMD2<Float>) -> Bool)?
    /// Runs once each time a border region first holds the player back.
    public var onBorderReached: (@MainActor () -> Void)?
    var wasAtBorder = false
    /// The player's breath under water (docs/engine/walk-mode.md).
    public var breath = PlayerBreath()
    /// The share of gait speed the player moves at this frame; nil moves at full speed.
    public var playerSpeedScale: (@MainActor () -> Float)?
    /// The vehicle pose the player rides at, where the body's root goes; nil on foot.
    public var playerSeat: float4x4? {
        didSet {
            if playerSeat == nil {
                seatedHead = nil
            }
        }
    }

    /// The seat idle's last `head` bone, in the seat's space. A seat idle that ended, or
    /// one still loading, keeps the eye there.
    var seatedHead: SIMD3<Float>?
    /// The player's mount; while one is under the player it moves instead of the
    /// player (docs/engine/riding.md).
    public weak var playerMount: (any PlayerMountDriving)?
    /// The furniture the player sits in; a move key asks it to stand the player up.
    public weak var playerFurniture: (any PlayerFurnitureDriving)?
    /// The waypoints a package walks the player along, empty without a walk
    /// (`PlayerPackageWalk`).
    public var playerWalkPath: [SIMD3<Float>] = []
    /// A straight package walk ignores static collision, as an NPC's straight leg does.
    public var playerWalkIgnoresStatics = false
    /// Called once when the player reaches the last waypoint of `playerWalkPath`.
    public var onPlayerWalkArrived: (() -> Void)?
    /// Paralysis: the player can look around but not move, jump, or attack.
    public var isPlayerParalysed = false

    public init() {}
}
