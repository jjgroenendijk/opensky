// The bridge after a landing: the graph stands when its landing clip ends, and a
// player who still moves must start its walk or run again.

@testable import OpenSkyBehavior
@testable import OpenSkyPhysics
@testable import OpenSkyPlayer
import OpenSkyRenderCore
@testable import OpenSkyRendering
import OpenSkyWorldInterface
import simd
import Testing

extension LocomotionBridgeTests {
    /// The graph stands when its landing clip ends, so a player who still walks
    /// starts moving again on the next step.
    @Test
    func theGraphStandingAfterALandingHearsMoveStartAgain() {
        var camera = Self.camera()
        var controller = WalkController(cameraPosition: camera.position)
        let bridge = LocomotionBridge(configuration: .synthetic, graph: Self.graph())
        Self.settle(&controller, camera: &camera, bridge: bridge)
        bridge.acceptFrame(CameraInput(moveForward: 1, dt: Self.step))
        Self.advance(&controller, camera: &camera, bridge: bridge, steps: 2)
        // The status keeps each raised name once, so clear it to see the next raise.
        bridge.updateStatus { $0.raisedEvents = [] }
        bridge.raise(LocomotionGraphNames.jumpLandEnd)
        Self.advance(&controller, camera: &camera, bridge: bridge, steps: 1)
        #expect(Self.raised(bridge, LocomotionGraphNames.moveStart) == 0)
        Self.advance(&controller, camera: &camera, bridge: bridge, steps: 1)
        #expect(Self.raised(bridge, LocomotionGraphNames.moveStart) == 1)
    }
}
