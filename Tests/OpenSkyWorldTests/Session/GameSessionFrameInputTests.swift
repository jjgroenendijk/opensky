// The renderer reads game state only from the input the session hands it once per
// frame. A change between frames reaches the renderer at the next frame, and never
// half way through one. Skips without a Metal 4 GPU.

import Metal
import OpenSkyEngineTesting
import OpenSkyFormatsESM
import OpenSkyPlayer
@testable import OpenSkyRendering
import OpenSkyTagsTesting
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
import simd
import Testing

@Suite(.tags(.gpu), .unlessPlanSkips(.gpu))
struct GameSessionFrameInputTests {
    private static let width = 64
    private static let height = 48

    @Test(.enabled(if: OffscreenRendererFixture.hasMetal4Device))
    @MainActor
    func aSessionChangeReachesTheRendererAtTheNextFrame() throws {
        let gameSession = try Self.makeSession()
        let renderer = gameSession.renderer
        gameSession.worldSimPaused = true
        gameSession.worldTimeScale = 0.5
        gameSession.timeOfDay = 6
        gameSession.freeFlyCamera.position += SIMD3(100, 0, 0)
        gameSession.instancePoses.dynamicDeltas[7] = matrix_identity_float4x4
        #expect(!renderer.frameInput.isPaused)

        _ = try renderer.renderOffscreen(width: Self.width, height: Self.height)

        let input = renderer.frameInput
        #expect(input.isPaused)
        #expect(input.timeScale == 0.5)
        #expect(abs(input.timeOfDay - 6) < 1e-4)
        #expect(input.view.position == gameSession.freeFlyCamera.position)
        #expect(input.instancePoses.revision == gameSession.instancePoses.revision)
        #expect(renderer.instanceDeltas[7] == matrix_identity_float4x4)
    }

    @Test(.enabled(if: OffscreenRendererFixture.hasMetal4Device))
    @MainActor
    func theProjectionFollowsTheInputFieldOfView() throws {
        let gameSession = try Self.makeSession()
        let renderer = gameSession.renderer
        _ = try renderer.renderOffscreen(width: Self.width, height: Self.height)
        let before = renderer.projectionMatrix

        gameSession.setMovementMode(.walk)
        gameSession.setFirstPersonFOVY(radians: 1.2)
        #expect(renderer.projectionMatrix == before)
        _ = try renderer.renderOffscreen(width: Self.width, height: Self.height)

        #expect(renderer.frameInput.fovYRadians == gameSession.firstPersonCamera.fovYRadians)
        #expect(renderer.frameInput.fovYRadians != FirstPersonCamera.defaultFOVYRadians)
        #expect(renderer.projectionMatrix != before)
    }

    /// A teleport in fly mode, then walk mode, stands the player on the spot.
    @Test(.enabled(if: OffscreenRendererFixture.hasMetal4Device))
    @MainActor
    func aFlyTeleportThenWalkStandsOnTheSpot() throws {
        let gameSession = try Self.makeSession()
        gameSession.setMovementMode(.fly)
        let spot = SIMD3<Float>(100, -50, 68)
        gameSession.reseedMovement(camera: .teleport(placement: .init(
            position: spot,
            rotation: .zero
        )))
        gameSession.setMovementMode(.walk)
        #expect(simd_distance(gameSession.walkController.feetPosition, spot) < 0.01)
    }

    @Test(.enabled(if: OffscreenRendererFixture.hasMetal4Device))
    @MainActor
    func aRendererWithoutASessionDrawsTheInputItsCallerSets() throws {
        let canvas = OffscreenCanvas(
            width: Self.width,
            height: Self.height,
            shaders: .packageFixture
        )
        let renderer = try canvas.makeRenderer()
        renderer.frameInput.timeOfDay = 20
        _ = try renderer.renderOffscreen(width: Self.width, height: Self.height)
        #expect(renderer.frameInput.timeOfDay == 20)
        #expect(renderer.frameDriver == nil)
    }

    @MainActor
    private static func makeSession() throws -> GameSession {
        try OffscreenCanvas(width: width, height: height, shaders: .packageFixture).makeSession()
    }
}
