import OpenSkyBehavior
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyPhysics
import simd

/// Who is shooting, and from where.
nonisolated public struct ProjectileShooter: Equatable, Sendable {
    /// The shooter's reference, so a shot can never hit its own owner.
    public let key: ReferenceKey
    /// The muzzle, world space. The eye rather than the bow hand: the aim ray
    /// is the camera's, and starting the arrow anywhere the camera is not makes
    /// a shot that lands off the reticle by the offset between them.
    public let origin: SIMD3<Float>
    /// The camera's forward direction, before the tilt-up angle is applied.
    public let aim: SIMD3<Float>
    /// Which perspective is active, which picks the tilt GMST.
    public let isFirstPerson: Bool
    /// The cell the shooter is standing in, which is the cell a stuck arrow is
    /// spawned into. Nil outside a streamed world, and then nothing sticks.
    public let location: CellSceneLocation?

    public init(
        key: ReferenceKey,
        origin: SIMD3<Float>,
        aim: SIMD3<Float>,
        isFirstPerson: Bool,
        location: CellSceneLocation?
    ) {
        self.key = key
        self.origin = origin
        self.aim = aim
        self.isFirstPerson = isFirstPerson
        self.location = location
    }

    /// A placed reference fires along its heading (rotation about Z, radians), level.
    /// Dart ports are turned 90 degrees about X, so their full facing points at the
    /// ceiling or the floor; docs/engine/traps.md "Firing a weapon".
    public static func headingAim(zRotation: Float) -> SIMD3<Float> {
        SIMD3(sinf(zRotation), cosf(zRotation), 0)
    }
}

/// One projectile in flight: an arrow or a cast spell.
nonisolated public struct LiveProjectile: Equatable, Sendable {
    /// Monotonic id, so the trace can name a projectile that no longer exists.
    public let id: Int
    public let shooter: ReferenceKey
    public let profile: ProjectileProfile
    /// What it carries and what it does when it lands. Fixed at launch, for the
    /// reason a bow's damage is: re-deriving it at impact would let a weapon
    /// swap or a re-ready mid-flight change what is already in the air.
    public let payload: ProjectilePayload
    public let launchPosition: SIMD3<Float>
    public let launchDirection: SIMD3<Float>
    /// The cell it was fired in, which is where a stick lands.
    public let location: CellSceneLocation?
    public var state: ProjectileFlightState
    /// A cone's travel at which the last look ahead found the world; nil while clear.
    public var coneStop: Float?
    /// The reference and material that look ahead found.
    public var coneWall: FormID?
    public var coneWallMaterial: FormID?
    /// The flight age of a cone's next look ahead.
    public var nextConeLook: Float = 0

    /// Where the shot is now, which is what a readout draws.
    public var position: SIMD3<Float> {
        state.position
    }

    public init(
        id: Int,
        shooter: ReferenceKey,
        profile: ProjectileProfile,
        payload: ProjectilePayload,
        launchPosition: SIMD3<Float>,
        launchDirection: SIMD3<Float>,
        location: CellSceneLocation?,
        state: ProjectileFlightState,
        coneStop: Float? = nil,
        coneWall: FormID? = nil,
        coneWallMaterial: FormID? = nil,
        nextConeLook: Float = 0
    ) {
        self.id = id
        self.shooter = shooter
        self.profile = profile
        self.payload = payload
        self.launchPosition = launchPosition
        self.launchDirection = launchDirection
        self.location = location
        self.state = state
        self.coneStop = coneStop
        self.coneWall = coneWall
        self.coneWallMaterial = coneWallMaterial
        self.nextConeLook = nextConeLook
    }
}
