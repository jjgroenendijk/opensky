// Shared setup for the locomotion-bridge suites (issue #188): the synthetic
// graph, the step state, and the controller driving helpers. Split out of
// `LocomotionBridgeTests` so both files stay inside the lint type-length cap.

@testable import opensky
import simd

extension LocomotionBridgeTests {
    static let up = SIMD3<Float>(0, 0, 1)
    static let step = WalkController.fixedTimeStep

    static func distanceForward(sprint: Bool, run: Bool, sneak: Bool) -> Float {
        let bridge = LocomotionBridge(configuration: .synthetic)
        bridge.intent = LocomotionIntent(
            moveForward: 1, run: run, sprint: sprint, sneak: sneak
        )
        return simd_length(bridge.plan(state()).horizontalDisplacement)
    }

    static func state(dt: Float = WalkController.fixedTimeStep) -> LocomotionStepState {
        LocomotionStepState(
            feetPosition: SIMD3<Float>(),
            verticalVelocity: 0,
            isGrounded: true,
            yaw: 0,
            dt: dt
        )
    }

    /// A graph declaring the census names the bridge writes, minus `SpeedWalk`
    /// and `SpeedRun`, so one missing name is exercised too.
    static func graph() -> BehaviorGraphInstance {
        let variables = [
            BehaviorVariableSpec(LocomotionGraphNames.speed, .real, 0),
            BehaviorVariableSpec(LocomotionGraphNames.speedSampled, .real, 0),
            BehaviorVariableSpec(LocomotionGraphNames.direction, .real, 0),
            BehaviorVariableSpec(LocomotionGraphNames.turnDelta, .real, 0),
            BehaviorVariableSpec(LocomotionGraphNames.isSprinting, .bool, 0),
            BehaviorVariableSpec(LocomotionGraphNames.isSneaking, .bool, 0),
            BehaviorVariableSpec(LocomotionGraphNames.isInSneak, .int32, 0),
            BehaviorVariableSpec(LocomotionGraphNames.inJumpState, .bool, 0)
        ]
        var table = BehaviorObjectTable()
        let root = table.add(
            BehaviorFixture.clipGenerator("idle", animationName: "idle"),
            at: 0x10
        )
        return BehaviorFixture.instance(
            root: root,
            table: table,
            data: BehaviorFixture.graphData(
                variables: variables, events: LocomotionGraphNames.events
            )
        )
    }

    /// A graph running one clip whose root bone ramps 30 units along +X per
    /// second — an order of magnitude more drift than a vanilla clip's jitter,
    /// so a test that passes here would have failed under any speed threshold.
    /// `carriesExtractedMotion` is the only thing that differs between the two
    /// clips this builds.
    static func rampGraph(carriesExtractedMotion: Bool) throws -> BehaviorGraphInstance {
        let clip = try BehaviorFixture.splineClip(
            boneIndex: 0, carriesExtractedMotion: carriesExtractedMotion
        )
        var table = BehaviorObjectTable()
        let root = table.add(
            BehaviorFixture.clipGenerator("walk", animationName: "walk"), at: 0x10
        )
        return BehaviorFixture.instance(
            root: root,
            table: table,
            data: BehaviorFixture.graphData(
                variables: [], events: LocomotionGraphNames.events
            ),
            clips: BehaviorClipTable(byName: ["walk": clip])
        )
    }

    /// How far the ramp clip's root bone travels over one fixed step.
    static let rampTravelPerStep: Float = 30 * WalkController.fixedTimeStep

    static func raised(_ bridge: LocomotionBridge, _ name: String) -> Int {
        bridge.status.raisedEvents.filter { $0 == name }.count
    }

    static func camera() -> FreeFlyCamera {
        FreeFlyCamera(
            position: SIMD3<Float>(0, 0, PlayerCapsule.standard.eyeHeight),
            yaw: 0,
            pitch: 0
        )
    }

    static func settle(
        _ controller: inout WalkController,
        camera: inout FreeFlyCamera,
        bridge: LocomotionBridge
    ) {
        advance(&controller, camera: &camera, bridge: bridge, steps: 2)
    }

    static func advance(
        _ controller: inout WalkController,
        camera: inout FreeFlyCamera,
        bridge: LocomotionBridge,
        steps: Int
    ) {
        for _ in 0 ..< steps {
            controller.update(
                camera: &camera,
                input: CameraInput(dt: step),
                sampleGround: flatGround,
                plan: { bridge.plan($0) }
            )
        }
    }

    static func flatGround(_: SIMD2<Float>) -> TerrainGroundSample? {
        TerrainGroundSample(height: 0, normal: up)
    }

    /// A tall box straddling the +X axis, so a capsule walking east runs into
    /// its west face.
    static func wall(atX x: Float) -> StaticCollisionShape {
        let half = SIMD3<Float>(8, 400, 400)
        let transform = MatrixMath.translation(SIMD3<Float>(x + half.x, 0, 0))
        let bounds = ModelBounds(min: -half, max: half)
        return StaticCollisionShape(
            reference: FormID(1),
            transform: transform,
            geometry: .convexVertices(
                vertices: CapsuleWorldCollider.boxVertices(half),
                hullIndices: CapsuleWorldCollider.boxIndices
            ),
            bounds: bounds.transformed(by: transform)
        )
    }
}
