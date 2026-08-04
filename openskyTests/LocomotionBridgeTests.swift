// Locomotion bridge over synthetic graphs and synthetic terrain (issue #188):
// gait speeds, the jump arc, the sneak toggle, swim enter and exit, blocked
// motion, and the paused-frame no-op.
//
// The graph here is a synthetic one built in code, declaring the same variable
// and event names the vanilla census reports. Nothing is extracted from the
// install (AGENTS.md "Legal & IP boundary"); the real graph is driven by
// `LocomotionBridgeRealDataTests`.

@testable import opensky
import simd
import Testing

struct LocomotionBridgeTests {
    // MARK: - Gaits

    @Test
    func gaitSpeedsSeparateWalkRunSprintAndSneak() {
        let configuration = PlayerMovementConfiguration.synthetic
        let bridge = LocomotionBridge(configuration: configuration)
        #expect(bridge.speed(of: .walk) == configuration.walkSpeed.value)
        #expect(bridge.speed(of: .run) == configuration.runSpeed.value)
        #expect(bridge.speed(of: .sprint) == configuration.sprintSpeed.value)
        #expect(bridge.speed(of: .sneak) == configuration.sneakSpeed.value)
        #expect(bridge.speed(of: .swim) == configuration.swimSpeed.value)
    }

    @Test
    func plannedDisplacementScalesWithTheResolvedGait() {
        let walk = Self.distanceForward(sprint: false, run: false, sneak: false)
        let run = Self.distanceForward(sprint: false, run: true, sneak: false)
        let sprint = Self.distanceForward(sprint: true, run: true, sneak: false)
        let sneak = Self.distanceForward(sprint: true, run: true, sneak: true)
        #expect(walk < run)
        #expect(run < sprint)
        // Sneak outranks both, so holding every key still crouches.
        #expect(sneak < walk)
    }

    @Test
    func standingStillPlansNoDisplacement() {
        let bridge = LocomotionBridge(configuration: .synthetic)
        let plan = bridge.plan(Self.state())
        #expect(plan.horizontalDisplacement == SIMD2<Float>())
        #expect(plan.motionSource == .idle)
    }

    // MARK: - Zero dt

    @Test
    func zeroDeltaTimeAdvancesNothingAndFiresNothing() {
        let graph = Self.graph()
        let bridge = LocomotionBridge(configuration: .synthetic, graph: graph)
        bridge.intent = LocomotionIntent(moveForward: 1, jump: true)

        let plan = bridge.plan(Self.state(dt: 0))

        #expect(plan == .still)
        #expect(bridge.status.graphUpdates == 0)
        #expect(bridge.status.raisedEvents.isEmpty)
        #expect(bridge.status.boundVariables.isEmpty)
        #expect(graph.variable(named: LocomotionGraphNames.speed) == .real(0))
    }

    @Test
    func aPausedFrameLeavesTheCapsuleWhereItWas() {
        var camera = Self.camera()
        var controller = WalkController(cameraPosition: camera.position)
        let bridge = LocomotionBridge(configuration: .synthetic)
        Self.settle(&controller, camera: &camera, bridge: bridge)
        let before = controller.feetPosition

        bridge.acceptFrame(CameraInput(moveForward: 1, dt: 0))
        controller.update(
            camera: &camera,
            input: CameraInput(moveForward: 1, dt: 0),
            sampleGround: Self.flatGround,
            plan: { bridge.plan($0) }
        )

        #expect(controller.feetPosition == before)
    }

    // MARK: - Graph writes

    @Test
    func writesTheCensusVariablesAndReportsUnknownOnes() {
        let graph = Self.graph()
        let bridge = LocomotionBridge(configuration: .synthetic, graph: graph)
        bridge.intent = LocomotionIntent(moveForward: 1, run: true)

        _ = bridge.plan(Self.state())

        #expect(
            graph.variable(named: LocomotionGraphNames.speed)
                == .real(PlayerMovementConfiguration.synthetic.runSpeed.value)
        )
        #expect(graph.variable(named: LocomotionGraphNames.direction) == .real(0))
        #expect(bridge.status.boundVariables.contains(LocomotionGraphNames.speed))
        // The synthetic graph deliberately declares no `SpeedWalk`, so the
        // bridge must report it rather than dropping the write silently.
        #expect(bridge.status.missingVariables.contains(LocomotionGraphNames.speedWalk))
        #expect(bridge.status.graphUpdates == 1)
    }

    @Test
    func raisesMoveStartOnceAndMoveStopOnRelease() {
        let graph = Self.graph()
        let bridge = LocomotionBridge(configuration: .synthetic, graph: graph)
        bridge.intent = LocomotionIntent(moveForward: 1)
        _ = bridge.plan(Self.state())
        _ = bridge.plan(Self.state())
        #expect(Self.raised(bridge, LocomotionGraphNames.moveStart) == 1)

        bridge.intent = .still
        _ = bridge.plan(Self.state())
        #expect(Self.raised(bridge, LocomotionGraphNames.moveStop) == 1)
    }

    @Test
    func sneakToggleRaisesOneStartAndOneStop() {
        let graph = Self.graph()
        let bridge = LocomotionBridge(configuration: .synthetic, graph: graph)
        bridge.intent = LocomotionIntent(sneak: true)
        _ = bridge.plan(Self.state())
        _ = bridge.plan(Self.state())
        #expect(Self.raised(bridge, LocomotionGraphNames.sneakStart) == 1)
        #expect(graph.variable(named: LocomotionGraphNames.isSneaking) == .bool(true))

        bridge.intent = .still
        _ = bridge.plan(Self.state())
        #expect(Self.raised(bridge, LocomotionGraphNames.sneakStop) == 1)
        #expect(graph.variable(named: LocomotionGraphNames.isSneaking) == .bool(false))
    }

    @Test
    func vanillaShapedRootMotionIsTooSmallToTakeAuthority() {
        // A graph whose root barely jitters — what an in-place vanilla clip
        // produces — must not become the movement source.
        let bridge = LocomotionBridge(configuration: .synthetic)
        bridge.intent = LocomotionIntent(moveForward: 1)
        let plan = bridge.plan(Self.state())
        #expect(plan.motionSource == .configuredSpeed)
        #expect(
            abs(simd_length(plan.horizontalDisplacement)
                - PlayerMovementConfiguration.synthetic.walkSpeed.value * Self.step) < 1e-4
        )
    }

    // MARK: - Jump

    @Test
    func jumpLeavesTheGroundRisesAndLandsWithOneLandEvent() {
        var camera = Self.camera()
        var controller = WalkController(cameraPosition: camera.position)
        let graph = Self.graph()
        let bridge = LocomotionBridge(configuration: .synthetic, graph: graph)
        Self.settle(&controller, camera: &camera, bridge: bridge)
        #expect(controller.isGrounded)

        bridge.acceptFrame(CameraInput(jump: true, dt: Self.step))
        Self.advance(&controller, camera: &camera, bridge: bridge, steps: 1)
        #expect(!controller.isGrounded)
        #expect(controller.verticalVelocity > 0)
        #expect(Self.raised(bridge, LocomotionGraphNames.jumpUp) == 1)

        var apex: Float = 0
        for _ in 0 ..< 240 {
            Self.advance(&controller, camera: &camera, bridge: bridge, steps: 1)
            apex = max(apex, controller.feetPosition.z)
            if controller.isGrounded, apex > 0 {
                break
            }
        }
        #expect(controller.isGrounded)
        // The takeoff speed is derived from a jump height, so the arc has to
        // reach roughly that height and come back.
        #expect(apex > 60)
        #expect(abs(controller.feetPosition.z) < 1e-3)
        #expect(Self.raised(bridge, LocomotionGraphNames.jumpLand) == 1)
    }

    @Test
    func aSecondJumpNeedsTheGroundBack() {
        var camera = Self.camera()
        var controller = WalkController(cameraPosition: camera.position)
        let bridge = LocomotionBridge(configuration: .synthetic, graph: Self.graph())
        Self.settle(&controller, camera: &camera, bridge: bridge)

        bridge.acceptFrame(CameraInput(jump: true, dt: Self.step))
        Self.advance(&controller, camera: &camera, bridge: bridge, steps: 1)
        let afterFirst = controller.verticalVelocity
        bridge.acceptFrame(CameraInput(jump: true, dt: Self.step))
        Self.advance(&controller, camera: &camera, bridge: bridge, steps: 1)

        #expect(controller.verticalVelocity < afterFirst)
        #expect(Self.raised(bridge, LocomotionGraphNames.jumpUp) == 1)
    }

    // MARK: - Swim

    @Test
    func swimStartsBelowTheThresholdAndStopsAboveIt() {
        var camera = Self.camera()
        var controller = WalkController(cameraPosition: camera.position)
        let graph = Self.graph()
        let bridge = LocomotionBridge(configuration: .synthetic, graph: graph)
        var surface: Float = 0
        bridge.sampleWater = { _ in surface }
        Self.settle(&controller, camera: &camera, bridge: bridge)
        #expect(!controller.isSwimming)

        // A 300-unit-deep column over the ground plane: deeper than the enter
        // threshold, and deep enough that floating leaves the capsule above the
        // ground rather than inside it.
        surface = 300
        Self.advance(&controller, camera: &camera, bridge: bridge, steps: 4)
        #expect(controller.isSwimming)
        #expect(Self.raised(bridge, LocomotionGraphNames.swimStart) == 1)
        // The swimmer rises to float with its eye at the surface rather than
        // sinking under gravity.
        Self.advance(&controller, camera: &camera, bridge: bridge, steps: 240)
        let floating = surface - PlayerCapsule.standard.eyeHeight
        #expect(abs(controller.feetPosition.z - floating) < 1)
        #expect(abs(controller.verticalVelocity) <= WalkController.maximumSwimVerticalSpeed)

        surface = 0
        Self.advance(&controller, camera: &camera, bridge: bridge, steps: 1)
        #expect(!controller.isSwimming)
        #expect(Self.raised(bridge, LocomotionGraphNames.swimStop) == 1)
        // Gravity has the capsule again: it falls back to the ground plane.
        Self.advance(&controller, camera: &camera, bridge: bridge, steps: 240)
        #expect(controller.isGrounded)
        #expect(abs(controller.feetPosition.z) < 1e-3)
    }

    @Test
    func swimmingHoldsDepthWithNoVerticalInput() {
        let bridge = LocomotionBridge(configuration: .synthetic)
        bridge.sampleWater = { _ in 200 }
        let plan = bridge.plan(Self.state())
        #expect(plan.isSwimming)
        #expect(plan.swimVerticalVelocity == 0)
        #expect(plan.swimSurfaceHeight == 200)
    }

    // MARK: - Collision

    @Test
    func blockedRootMotionDoesNotAccumulateThroughTheWall() {
        var camera = Self.camera()
        var controller = WalkController(cameraPosition: camera.position)
        let bridge = LocomotionBridge(configuration: .synthetic)
        Self.settle(&controller, camera: &camera, bridge: bridge)

        let wall = Self.wall(atX: 200)
        for _ in 0 ..< 240 {
            bridge.acceptFrame(CameraInput(moveForward: 1, dt: Self.step))
            controller.update(
                camera: &camera,
                input: CameraInput(moveForward: 1, dt: Self.step),
                sampleGround: Self.flatGround,
                collisionQuery: { _ in [wall] },
                plan: { bridge.plan($0) }
            )
        }

        // Two seconds of walking into a wall 200 units away: the capsule stops
        // at its radius from the face and never integrates past it.
        #expect(controller.feetPosition.x <= 200 - PlayerCapsule.standard.radius + 0.5)
        #expect(controller.feetPosition.x > 100)
    }
}
