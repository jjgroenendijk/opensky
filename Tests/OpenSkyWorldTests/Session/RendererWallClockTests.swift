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
import OpenSkyWorldTesting
import Testing

@Suite(.tags(.gpu), .unlessPlanSkips(.gpu))
@MainActor
struct RendererWallClockTests {
    private func makeSession(clock: ManualWallClock) throws -> GameSession {
        let device = try #require(ShadowSceneFixture.device)
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 64, height: 64), device: device)
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        return try GameSession(
            view: view,
            shaderLibrary: ShaderLibraryFixture.library(device: device),
            wallClock: clock
        )
    }

    @Test(.enabled(if: ShadowSceneFixture.hasMetal4Device))
    func gameClockAdvancesByTheManualStepTimesTimescale() throws {
        let clock = ManualWallClock(now: 100)
        let gameSession = try makeSession(clock: clock)
        gameSession.gameClock = GameClock(totalGameSeconds: 0)

        gameSession.advanceGameClockFromWallClock()
        clock.advance(by: 0.05)
        gameSession.advanceGameClockFromWallClock()

        let expected = 0.05 * Double(GameClock.defaultTimescale)
        #expect(abs(gameSession.gameClock.totalGameSeconds - expected) < 1e-6)
    }

    @Test(.enabled(if: ShadowSceneFixture.hasMetal4Device))
    func pausedRendererIgnoresTheManualStep() throws {
        let clock = ManualWallClock()
        let gameSession = try makeSession(clock: clock)
        let renderer = gameSession.renderer
        renderer.updateAnimationsFromWallClock()
        gameSession.worldSimPaused = true
        clock.advance(by: 0.05)
        // A frame adopts the session's pause before it steps the animations.
        renderer.adoptFrameInput(gameSession.frameInput)

        #expect(renderer.updateAnimationsFromWallClock() == 0)
        gameSession.worldSimPaused = false
        clock.advance(by: 0.02)
        renderer.adoptFrameInput(gameSession.frameInput)
        #expect(abs(renderer.updateAnimationsFromWallClock() - 0.02) < 1e-6)
    }
}
