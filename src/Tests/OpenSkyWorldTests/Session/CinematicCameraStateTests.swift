// The cinematic camera state a session starts with.

import OpenSkyWorldInterface
import Testing

@MainActor
struct CinematicCameraStateTests {
    @Test func aNewSessionPlaysNoShotAndNoShake() {
        let state = RendererCinematicCameraState()
        #expect(state.pose == nil)
        #expect(state.shakeOffset == .zero)
        #expect(!state.isCollisionLimited)
    }
}
