// Swimming against synthetic water and ground: when it starts and stops, the float depth,
// walking out onto a shore, a steep shore, and the jump out of the water. No game assets.

import OpenSkyEngineTesting
@testable import OpenSkyFormatsCore
@testable import OpenSkyPhysics
@testable import OpenSkyPlayer
@testable import OpenSkyRenderCore
@testable import OpenSkyRendering
import OpenSkyWorldInterface
import simd
import Testing

struct SwimRuleTests {
    @Test
    func submersionIsTheFeetDepthOverTheBodyHeight() {
        #expect(SwimRule.submersion(surface: 0, feetHeight: -96, bodyHeight: 128) == 0.75)
        #expect(SwimRule.submersion(surface: 0, feetHeight: -500, bodyHeight: 128) == 1)
        #expect(SwimRule.submersion(surface: 0, feetHeight: 10, bodyHeight: 128) == 0)
    }

    @Test
    func depthAloneStartsASwim() {
        #expect(SwimRule.swims(Self.contact(0.7, swimming: false, ground: true)))
        #expect(!SwimRule.swims(Self.contact(0.69, swimming: false, ground: false)))
        #expect(!SwimRule.swims(Self.contact(0.9, swimming: false, ground: false, rising: true)))
    }

    @Test
    func aSwimStopsInShallowWaterOnlyWithGroundBelow() {
        #expect(!SwimRule.swims(Self.contact(0.69, swimming: true, ground: true)))
        #expect(SwimRule.swims(Self.contact(0.7, swimming: true, ground: true)))
        #expect(SwimRule.swims(Self.contact(0.2, swimming: true, ground: false)))
        #expect(!SwimRule.swims(Self.contact(0.005, swimming: true, ground: false)))
    }

    @Test
    func theFloatPointRestsTenUnitsUnderTheSurface() {
        // Body height 128 and float level 1.3: the float point is 83.2 units up.
        let feet = SwimRule.restingFeetHeight(surface: 0, bodyHeight: 128, floatLevel: 1.3)
        #expect(abs(feet + 93.2) < 1e-3)
        let npcFeet = SwimRule.restingFeetHeight(surface: 0, bodyHeight: 128, floatLevel: 1.6)
        #expect(abs(npcFeet + 112.4) < 1e-3)
    }

    static func contact(
        _ submersion: Float, swimming: Bool, ground: Bool, rising: Bool = false
    ) -> SwimContact {
        SwimContact(
            submersion: submersion, wasSwimming: swimming, hasGroundBelow: ground, isRising: rising
        )
    }
}

struct WalkControllerSwimTests {
    @Test
    func aSwimmerFloatsWithItsFloatPointJustUnderTheSurface() {
        let drive = SwimDrive()
        var camera = CapsuleCollisionTests.camera(feet: SIMD3(-2000, 0, -40))
        var controller = WalkController(cameraPosition: camera.position)
        drive.run(&controller, camera: &camera, input: CameraInput(), steps: 1200)

        #expect(controller.isSwimming)
        let floatPoint = SwimRule.floatPointHeight(
            feetHeight: controller.feetPosition.z,
            bodyHeight: PlayerCapsule.standard.height,
            floatLevel: SwimRule.firstPersonFloatLevel
        )
        #expect(-floatPoint >= 0)
        #expect(-floatPoint <= SwimRule.floatRestDepth + 1)
    }

    @Test
    func aSwimmerWalksOutOntoAShore() {
        let drive = SwimDrive(ground: SwimDrive.shore(degrees: 30))
        var camera = CapsuleCollisionTests.camera(feet: SIMD3(-200, 0, -93))
        var controller = WalkController(cameraPosition: camera.position)
        var underTheBank = false
        var swam = false
        for _ in 0 ..< 360 {
            drive.run(&controller, camera: &camera, input: SwimDrive.forward, steps: 1)
            swam = swam || controller.isSwimming
            let bank = drive.ground(SIMD2(controller.feetPosition.x, 0))?.height ?? 0
            underTheBank = underTheBank || controller.feetPosition.z < bank - 0.5
        }

        #expect(swam)
        #expect(!underTheBank)
        #expect(!controller.isSwimming)
        #expect(controller.isGrounded)
        #expect(controller.feetPosition.x > 250)
    }

    @Test
    func aShoreSteeperThan47DegreesKeepsTheSwimmerInTheWater() {
        let drive = SwimDrive(ground: SwimDrive.shore(degrees: 60))
        var camera = CapsuleCollisionTests.camera(feet: SIMD3(-200, 0, -93))
        var controller = WalkController(cameraPosition: camera.position)
        drive.run(&controller, camera: &camera, input: SwimDrive.forward, steps: 360)

        #expect(controller.isSwimming)
        #expect(controller.feetPosition.z < -80)
    }

    @Test
    func aJumpAtTheSurfaceLiftsTheSwimmerOntoALowQuay() {
        // A quay whose top is 30 units above the water.
        let quay = DynamicBodyScene.box(center: SIMD3(300, 0, -485), half: SIMD3(270, 200, 515))
        let drive = SwimDrive(query: DynamicBodyScene.candidateQuery([quay]))
        var camera = CapsuleCollisionTests.camera(feet: SIMD3(-30, 0, -93))
        var controller = WalkController(cameraPosition: camera.position)
        drive.run(&controller, camera: &camera, input: SwimDrive.forward, steps: 120)
        #expect(controller.isSwimming)
        #expect(controller.feetPosition.x < 30)

        var jump = SwimDrive.forward
        jump.jump = true
        drive.run(&controller, camera: &camera, input: jump, steps: 1)
        #expect(!controller.isSwimming)
        drive.run(&controller, camera: &camera, input: SwimDrive.forward, steps: 120)

        #expect(!controller.isSwimming)
        #expect(controller.isGrounded)
        #expect(abs(controller.feetPosition.z - 30) < 0.5)
        #expect(controller.feetPosition.x > 60)
    }
}

/// The player's bridge over still water at height 0, on synthetic ground and meshes.
struct SwimDrive {
    static let forward = CameraInput(moveForward: 1, dt: WalkController.fixedTimeStep)

    let bridge: LocomotionBridge
    let ground: WalkController.GroundSampler
    let query: WalkController.CollisionQuery

    init(
        ground: @escaping WalkController.GroundSampler = { _ in
            TerrainGroundSample(height: -1000, normal: SIMD3(0, 0, 1))
        },
        query: @escaping WalkController.CollisionQuery = { _ in [] }
    ) {
        bridge = LocomotionBridge(configuration: .synthetic)
        bridge.sampleWater = { _ in WaterReading(surface: 0) }
        self.ground = ground
        self.query = query
    }

    /// A lake bed 150 units under the surface, rising east of x = 0 at `degrees`.
    static func shore(degrees: Float) -> WalkController.GroundSampler {
        let rise = tanf(MatrixMath.radians(fromDegrees: degrees))
        let normal = simd_normalize(SIMD3<Float>(-rise, 0, 1))
        return { position in
            position.x < 0
                ? TerrainGroundSample(height: -150, normal: SIMD3(0, 0, 1))
                : TerrainGroundSample(height: -150 + position.x * rise, normal: normal)
        }
    }

    func run(
        _ controller: inout WalkController,
        camera: inout FreeFlyCamera,
        input: CameraInput,
        steps: Int
    ) {
        var frame = input
        frame.dt = WalkController.fixedTimeStep
        for _ in 0 ..< steps {
            bridge.acceptFrame(frame)
            controller.update(
                camera: &camera,
                input: frame,
                sampleGround: ground,
                collisionQuery: query,
                plan: { bridge.plan($0) }
            )
        }
    }
}
