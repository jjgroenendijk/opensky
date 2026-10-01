// The Player & Locomotion and First person panels. Without a renderer both
// report an "unavailable" snapshot.

import OpenSkyBehavior
import OpenSkyFormatsCore
import OpenSkyPhysics
import OpenSkyRendering
import simd

extension PlayerCoordinator: PlayerLocomotionControlProviding {
    public var playerLocomotionSnapshot: PlayerLocomotionSnapshot {
        guard let world, let bridge = world.playerLocomotion else { return .unavailable }
        return PlayerLocomotionSnapshot(
            rendererAvailable: true,
            walkModeActive: world.isWalkModeActive,
            status: bridge.status,
            bindings: PlayerCore.bindings(
                run: bridge.intent.run,
                sprint: input.isSprinting,
                sneak: input.isSneaking,
                airborne: !world.isPlayerGrounded
            ),
            configuration: bridge.configuration,
            activeStates: bridge.graph?.activeStates ?? [],
            firstPersonActiveStates: bridge.firstPersonGraph?.activeStates ?? [],
            variables: PlayerCore.variables(of: bridge.graph),
            forcedGait: bridge.forcedGait,
            tally: bridge.graph?.tally,
            bodyFailureReason: failureReason
        )
    }

    public var isSneaking: Bool {
        get { input.isSneaking }
        set {
            guard input.isSneaking != newValue else { return }
            input.toggleSneak()
        }
    }

    public var forcedLocomotionGait: LocomotionGait? {
        get { world?.playerLocomotion?.forcedGait }
        set { world?.playerLocomotion?.forcedGait = newValue }
    }

    public func requestJump() {
        input.requestJump()
    }

    @discardableResult
    public func raiseLocomotionEvent(named name: String) -> Bool {
        world?.playerLocomotion?.raiseGraphEvent(named: name) ?? false
    }

    public func clearLocomotionTrace() {
        world?.playerLocomotion?.clearMotionTrace()
    }
}

extension PlayerCoordinator: FirstPersonControlProviding {
    public var firstPersonSnapshot: FirstPersonSnapshot {
        guard
            let world,
            let status = world.playerLocomotion?.status,
            let fovY = world.firstPersonFOVYRadians
        else { return .unavailable }
        let rig = world.playerFirstPersonRig
        return FirstPersonSnapshot(
            rendererAvailable: true,
            active: world.areFirstPersonArmsVisible,
            graphAttached: status.firstPersonGraphAvailable,
            rigAttached: rig != nil,
            failureReason: firstPersonFailureReason,
            armModelCount: rig?.assembly.models.count ?? 0,
            droppedPieceCount: PlayerCore.droppedPieceCount(of: rig),
            hasCameraBone: rig?.cameraBoneIndex != nil,
            cameraBoneHeight: rig?.cameraBoneMatrix?.columns.3.z,
            graphUpdates: status.firstPersonGraphUpdates,
            missingVariables: status.firstPersonMissingVariables,
            missingEvents: status.firstPersonMissingEvents,
            fovYDegrees: MatrixMath.degrees(fromRadians: fovY)
        )
    }

    public var firstPersonFOVYDegrees: Float {
        get {
            MatrixMath.degrees(
                fromRadians: world?.firstPersonFOVYRadians ?? FirstPersonCamera.defaultFOVYRadians
            )
        }
        set {
            world?.setFirstPersonFOVY(radians: MatrixMath.radians(fromDegrees: newValue))
        }
    }

    public var firstPersonArmsEnabled: Bool {
        get { world?.firstPersonArmsEnabled ?? true }
        set { world?.setFirstPersonArmsEnabled(newValue) }
    }
}
