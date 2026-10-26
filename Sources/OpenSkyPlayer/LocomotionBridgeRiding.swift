// A rider step: the player's graph follows the mount. The mount's own bridge moves the
// mount (PlayerMountDrive.swift); this one only tells the rider's graph how the mount
// moves, so `0_master.hkx` picks the riding clips. See docs/engine/riding.md.

import OpenSkyActorPresentation
import OpenSkyBehavior
import OpenSkyPhysics
import simd

/// How the mount under the rider moved in the last step.
nonisolated public struct MountMotion: Equatable, Sendable {
    /// Horizontal speed, world units per second.
    public var speed: Float = 0
    /// Yaw change of the last step, radians, counter-clockwise.
    public var turnDelta: Float = 0
    public var isSprinting = false
    /// A flying mount's climb angle, radians; positive climbs.
    public var pitch: Float = 0

    public static let still = MountMotion()

    public init(
        speed: Float = 0, turnDelta: Float = 0, isSprinting: Bool = false, pitch: Float = 0
    ) {
        self.speed = speed
        self.turnDelta = turnDelta
        self.isSprinting = isSprinting
        self.pitch = pitch
    }

    public var isMoving: Bool {
        speed > 0.5
    }
}

nonisolated extension LocomotionBridge {
    /// Steps the rider's graph on a mount. `feet` is the saddle the rider sits on, and
    /// `yaw` the mount's heading. The rider neither walks nor falls.
    public func advanceRiding(
        deltaTime: Float, feet: SIMD3<Float>, yaw: Float, mount: MountMotion
    ) {
        updateStatus { status in
            status.feetPosition = feet
            status.lastPlan = .still
            status.verticalVelocity = 0
            status.isGrounded = true
        }
        guard deltaTime > 0 else { return }
        let stance = MountGraphNames.combatStanceEvent(
            from: wasCombatStance, to: actorState.weaponDrawn
        )
        let speed = mount.isMoving ? mount.speed : 0
        write(.real(speed), to: LocomotionGraphNames.speed)
        write(.real(speed), to: LocomotionGraphNames.speedSampled)
        write(.real(0), to: LocomotionGraphNames.direction)
        write(.real(mount.turnDelta), to: LocomotionGraphNames.turnDelta)
        write(.bool(mount.isSprinting), to: LocomotionGraphNames.isSprinting)
        write(.bool(false), to: LocomotionGraphNames.isSneaking)
        write(.real(mount.pitch), to: DragonFlightGraphNames.riderPitchOffset)
        writeCharacterVariables(state: LocomotionStepState(
            feetPosition: feet, verticalVelocity: 0, isGrounded: true, yaw: yaw, dt: deltaTime
        ))
        actorState.riding = mount.isSprinting ? .sprinting : .riding
        writeActorState(gait: mount.isSprinting ? .sprint : .run)
        if let stance {
            raise(stance)
        }
        if let pendingIdle {
            raise(pendingIdle.event)
            self.pendingIdle = nil
        }
        if mount.isMoving != wasMoving {
            raise(mount.isMoving ? LocomotionGraphNames.moveStart : LocomotionGraphNames.moveStop)
        }
        if mount.isSprinting != wasSprinting {
            raise(
                mount.isSprinting
                    ? LocomotionGraphNames.sprintStart : LocomotionGraphNames.sprintStop
            )
        }
        _ = advanceGraph(deltaTime: deltaTime)
        wasMoving = mount.isMoving
        wasSprinting = mount.isSprinting
        wasGrounded = true
    }
}
