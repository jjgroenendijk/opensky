// The ridden mount's movement. It runs the mount's own graph through a second
// locomotion bridge and capsule, so the horse plays its own gaits, and the rider's
// graph only follows (LocomotionBridgeRiding.swift). See docs/engine/riding.md.

import OpenSkyActorPresentation
import OpenSkyBehavior
import OpenSkyFormatsESM
import OpenSkyPhysics
import OpenSkyRendering
import simd

/// The ground and collision one mount step runs against.
public struct MountStepWorld {
    public let sampleGround: WalkController.GroundSampler
    public let collisionQuery: WalkController.CollisionQuery

    public init(
        sampleGround: @escaping WalkController.GroundSampler,
        collisionQuery: @escaping WalkController.CollisionQuery
    ) {
        self.sampleGround = sampleGround
        self.collisionQuery = collisionQuery
    }
}

/// What starting a mount drive needs.
public struct PlayerMountDriveStart {
    public let mount: ReferenceKey
    public let kind: MountKind
    public let saddleBone: String
    public let feet: SIMD3<Float>
    /// Walk yaw, counter-clockwise from +X.
    public let yaw: Float
    /// The mount's graph, lent by the actor graphs, and the buffer its playback draws.
    public let graph: BehaviorGraphInstance?
    public let pose: PlayerPoseBuffer
    public let configuration: PlayerMovementConfiguration

    public init(
        mount: ReferenceKey, kind: MountKind, saddleBone: String, feet: SIMD3<Float>,
        yaw: Float, graph: BehaviorGraphInstance?, pose: PlayerPoseBuffer,
        configuration: PlayerMovementConfiguration
    ) {
        self.mount = mount
        self.kind = kind
        self.saddleBone = saddleBone
        self.feet = feet
        self.yaw = yaw
        self.graph = graph
        self.pose = pose
        self.configuration = configuration
    }
}

public final class PlayerMountDrive {
    public let mount: ReferenceKey
    public let kind: MountKind
    public let saddleBone: String
    public let bridge: LocomotionBridge
    public private(set) var walk: WalkController
    /// Walk yaw, counter-clockwise from +X.
    public private(set) var heading: Float
    public private(set) var motion = MountMotion.still
    /// False during the mount and dismount clips, and for a dragon, which OpenSky does
    /// not fly: the mount stands still.
    public var isSteerable = false
    public var settings = MountSettings.vanilla
    private let events: LocomotionGraphEventQueue.Consumer

    public init(_ start: PlayerMountDriveStart) {
        mount = start.mount
        kind = start.kind
        saddleBone = start.saddleBone
        heading = start.yaw
        walk = WalkController(
            cameraPosition: start.feet + SIMD3(0, 0, MountMovementTypes.capsule.eyeHeight),
            capsule: MountMovementTypes.capsule,
            configuration: start.configuration
        )
        bridge = LocomotionBridge(
            configuration: start.configuration, graph: start.graph, pose: start.pose
        )
        bridge.isPlayerGraph = false
        events = bridge.graphEvents.addConsumer()
    }

    /// Steps the mount by one input frame, steered by the rider's input against the
    /// camera yaw. Returns the events its graph fired.
    public func advance(
        input: CameraInput, cameraYaw: Float, weaponDrawn: Bool, world: MountStepWorld
    ) -> [String] {
        let deltaTime = min(max(input.dt, 0), WalkController.maximumFrameTime)
        let steerable = isSteerable && kind == .horse
        let steer = steerable
            ? MountRules.steer(
                heading: heading, forward: input.moveForward, right: input.moveRight,
                cameraYaw: cameraYaw, deltaTime: deltaTime, turnRate: settings.turnRate
            )
            : MountSteer(heading: heading, throttle: 0)
        let start = walk.feetPosition
        let previousHeading = heading
        heading = steer.heading
        var mountInput = CameraInput(dt: input.dt)
        mountInput.moveForward = steer.throttle
        mountInput.boost = input.boost
        mountInput.sprint = steerable && input.sprint
        if steerable, input.jump {
            let moving = steer.throttle > 0
            mountInput.jump = moving
            bridge.raise(moving ? MountGraphNames.forwardJumpStart : MountGraphNames.standingRearUp)
        }
        raiseStance(weaponDrawn)
        bridge.acceptFrame(mountInput)
        walk.update(
            frameTime: input.dt, yaw: heading, sampleGround: world.sampleGround,
            collisionQuery: world.collisionQuery,
            plan: { [bridge] state in bridge.plan(state) }
        )
        let travel = walk.feetPosition - start
        motion = MountMotion(
            speed: deltaTime > 0 ? simd_length(SIMD2(travel.x, travel.y)) / deltaTime : 0,
            turnDelta: remainder(heading - previousHeading, 2 * Float.pi),
            isSprinting: bridge.status.gait == .sprint && steer.throttle > 0
        )
        return bridge.graphEvents.drain(events)
    }

    /// The mount's draw transform: feet and heading.
    public var transform: (feet: SIMD3<Float>, yaw: Float) {
        (walk.feetPosition, heading)
    }

    private func raiseStance(_ weaponDrawn: Bool) {
        bridge.write(
            .int(MountGraphNames.combatStanceValue(weaponDrawn)), to: MountGraphNames.combatStance
        )
        if
            let event = MountGraphNames.combatStanceEvent(
                from: bridge.wasCombatStance, to: weaponDrawn
            )
        {
            bridge.raise(event)
        }
        bridge.wasCombatStance = weaponDrawn
    }
}

/// What the session asks of the player's mount each frame. The app's mount adapter
/// conforms: it applies the commands the step returns.
@MainActor
public protocol PlayerMountDriving: AnyObject {
    /// A mount is under the player, in any phase.
    var isMountActive: Bool { get }
    /// How far, in radians, the rider may look down.
    var maximumLookDown: Float { get }
    /// Steps the mount by one input frame. Nil when no mount is under the player.
    func advanceMount(
        input: CameraInput, cameraYaw: Float, weaponDrawn: Bool, world: MountStepWorld
    ) -> (motion: MountMotion, yaw: Float)?
}
