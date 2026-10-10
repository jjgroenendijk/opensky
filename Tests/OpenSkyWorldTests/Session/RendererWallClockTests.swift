// The live frame clocks read the renderer's `WallClock`, so a manual clock
// steps game time and world time by an exact amount.

import Foundation
import Metal
import MetalKit
import OpenSkyEngineTesting
@testable import OpenSkyRendering
import OpenSkyTagsTesting
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
import OpenSkyWorldState
import Testing

@Suite(.tags(.gpu))
@MainActor
struct RendererWallClockTests {
    private func makeRenderer(clock: ManualWallClock) throws -> Renderer {
        let device = try #require(ShadowSceneFixture.device)
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 64, height: 64), device: device)
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        return try Renderer(
            view: view,
            shaderLibrary: ShaderLibraryFixture.library(device: device),
            wallClock: clock
        )
    }

    @Test(.enabled(if: ShadowSceneFixture.hasMetal4Device))
    func gameClockAdvancesByTheManualStepTimesTimescale() throws {
        let clock = ManualWallClock(now: 100)
        let renderer = try makeRenderer(clock: clock)
        renderer.gameClock = GameClock(totalGameSeconds: 0)

        renderer.advanceGameClockFromWallClock()
        clock.advance(by: 0.05)
        renderer.advanceGameClockFromWallClock()

        let expected = 0.05 * Double(GameClock.defaultTimescale)
        #expect(abs(renderer.gameClock.totalGameSeconds - expected) < 1e-6)
    }

    @Test(.enabled(if: ShadowSceneFixture.hasMetal4Device))
    func pausedRendererIgnoresTheManualStep() throws {
        let clock = ManualWallClock()
        let renderer = try makeRenderer(clock: clock)
        renderer.updateAnimationsFromWallClock()
        renderer.worldSimPaused = true
        clock.advance(by: 0.05)

        #expect(renderer.updateAnimationsFromWallClock() == 0)
        renderer.worldSimPaused = false
        clock.advance(by: 0.02)
        #expect(abs(renderer.updateAnimationsFromWallClock() - 0.02) < 1e-6)
    }
}
