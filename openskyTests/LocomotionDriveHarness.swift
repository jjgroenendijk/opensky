// The driving half of the env-gated locomotion drive (issue #188): the capsule,
// the camera, the bridge, the real terrain they run over, and the trace they
// write. Split out of `LocomotionBridgeRealDataTests` so both files stay inside
// the lint size caps, and kept free of assertions so the test file owns every
// expectation.
//
// Nothing here reads game data on its own; the test hands it a height field it
// already loaded from the user's install (never committed — AGENTS.md
// "Legal & IP").

@testable import opensky
import simd

/// One held input driven for a number of fixed steps.
struct LocomotionDriveResult {
    /// Horizontal distance travelled over the run, world units.
    let distance: Float
    /// True when no step moved the capsule backwards along +X.
    let isMonotoneForward: Bool
}

/// What one jump produced.
struct LocomotionJumpResult {
    let floor: Float
    let apex: Float
    let leftGround: Bool
    let landed: Bool
}

final class LocomotionDriveHarness {
    let bridge: LocomotionBridge
    private(set) var controller: WalkController
    private(set) var camera: FreeFlyCamera
    private let ground: WalkController.GroundSampler
    private(set) var log: [String] = []

    static let step = WalkController.fixedTimeStep
    /// One second of stepping at the controller's own rate.
    static let secondOfSteps = Int((1 / WalkController.fixedTimeStep).rounded())

    init(
        bridge: LocomotionBridge,
        terrain: TerrainHeightField,
        start: SIMD3<Float>
    ) {
        self.bridge = bridge
        ground = { terrain.sample(at: $0) }
        camera = FreeFlyCamera(
            position: start + SIMD3<Float>(0, 0, PlayerCapsule.standard.eyeHeight),
            yaw: 0,
            pitch: 0
        )
        controller = WalkController(
            cameraPosition: camera.position, configuration: bridge.configuration
        )
    }

    func note(_ line: String) {
        log.append(line)
    }

    /// Runs `steps` fixed steps of one held input and reports how far the
    /// capsule travelled and whether every step moved it forward.
    func run(input: CameraInput, steps: Int, label: String) -> LocomotionDriveResult {
        let start = controller.feetPosition
        var previousX = start.x
        var monotone = true
        for index in 0 ..< steps {
            bridge.acceptFrame(input)
            advance(input: input)
            if controller.feetPosition.x < previousX {
                monotone = false
            }
            previousX = controller.feetPosition.x
            if index % 30 == 0 {
                note(
                    "\(label) step \(index): x \(controller.feetPosition.x), "
                        + "z \(controller.feetPosition.z), "
                        + "gait \(bridge.status.gait.rawValue), "
                        + "source \(bridge.status.motionSource)"
                )
            }
        }
        let distance = simd_length(
            SIMD2(controller.feetPosition.x - start.x, controller.feetPosition.y - start.y)
        )
        note("\(label): travelled \(distance) units over \(steps) steps")
        return LocomotionDriveResult(distance: distance, isMonotoneForward: monotone)
    }

    /// Presses jump once and steps until the capsule is back on the ground, or
    /// until `steps` runs out.
    func jump(steps: Int) -> LocomotionJumpResult {
        let floor = controller.feetPosition.z
        bridge.acceptFrame(CameraInput(jump: true, dt: Self.step))
        var apex = floor
        var leftGround = false
        var landed = false
        for _ in 0 ..< steps {
            advance(input: CameraInput(dt: Self.step))
            apex = max(apex, controller.feetPosition.z)
            if !controller.isGrounded {
                leftGround = true
            } else if leftGround {
                landed = true
                break
            }
        }
        note("jump: floor \(floor), apex \(apex), landed \(landed)")
        return LocomotionJumpResult(
            floor: floor, apex: apex, leftGround: leftGround, landed: landed
        )
    }

    private func advance(input: CameraInput) {
        controller.update(
            camera: &camera,
            input: input,
            sampleGround: ground,
            plan: { [bridge] state in bridge.plan(state) }
        )
    }
}
