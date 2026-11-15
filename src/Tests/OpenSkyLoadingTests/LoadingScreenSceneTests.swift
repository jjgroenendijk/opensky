// The game's loading screen scene: the fixed camera, the path formula, the narrow
// view, the model's placement order, and the three lights.

import OpenSkyFormatsESM
@testable import OpenSkyLoading
import OpenSkyRenderCore
import simd
import Testing

struct LoadingScreenSceneTests {
    private static func close(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>) -> Bool {
        simd_length(lhs - rhs) < 1e-4
    }

    private static func axis(_ transform: float4x4, _ column: Int) -> SIMD3<Float> {
        let value = transform[column]
        return SIMD3(value.x, value.y, value.z)
    }

    @Test func theCameraLooksFromItsBaseAtTheTarget() {
        let camera = LoadingScreenScene.camera()
        #expect(camera.position == [-50, 600, 80])
        let toTarget = simd_normalize(SIMD3<Float>(-50, 0, 0) - camera.position)
        #expect(Self.close(camera.forward, toTarget))
    }

    @Test func thePathSubtractsOnTheFlatAxesAndAddsUp() {
        let camera = LoadingScreenScene.camera(pathNode: [3, -25, 35])
        #expect(camera.position == [-53, 625, 115])
        #expect(Self.close(camera.forward, LoadingScreenScene.camera().forward))
    }

    @Test func seventyFiveIsAboutSeventeenDegreesWide() {
        let degrees = LoadingScreenScene.horizontalFieldOfView(75) * 180 / .pi
        #expect(abs(degrees - 16.97) < 0.01)
    }

    @Test func theBaseTurnIsHalfATurnAboutZ() {
        let pose = LoadingScreenScene.ModelPose(
            rotationDegrees: .zero, scale: -2, translation: [4, 0, -30]
        )
        let transform = LoadingScreenScene.modelTransform(pose, aspectRatio: 16.0 / 9.0)
        #expect(Self.close(Self.axis(transform, 0), [-2, 0, 0]), "SNAM's sign is dropped")
        #expect(Self.axis(transform, 3) == [4, 0, -30])
    }

    @Test func anInventoryMarkerReplacesTheBaseTurn() {
        let pose = LoadingScreenScene.ModelPose(
            rotationDegrees: .zero, scale: 1, translation: .zero, markerRotation: .zero
        )
        let transform = LoadingScreenScene.modelTransform(pose, aspectRatio: 1)
        #expect(Self.close(Self.axis(transform, 0), [1, 0, 0]))
    }

    @Test func rnamTurnsLikeANIFMatrixThenThePlayerTurnsAboutTheSceneUp() {
        var pose = LoadingScreenScene.ModelPose(
            rotationDegrees: [0, 0, 90], scale: 1, translation: .zero, markerRotation: .zero
        )
        let initial = LoadingScreenScene.modelTransform(pose, aspectRatio: 1)
        #expect(Self.close(Self.axis(initial, 0), [0, -1, 0]))
        pose.rotationDegrees = [90, 0, 0]
        pose.turnRadians = .pi / 2
        let turned = LoadingScreenScene.modelTransform(pose, aspectRatio: 1)
        // RNAM tips the model's Y axis down; the turn then swings it about the scene's Z.
        #expect(Self.close(Self.axis(turned, 1), [0, 0, -1]))
        #expect(Self.close(Self.axis(turned, 0), [0, 1, 0]))
    }

    @Test func aWideScreenShrinksTheScaleAndTheOffset() {
        let pose = LoadingScreenScene.ModelPose(
            rotationDegrees: .zero, scale: 1, translation: [10, 0, -20], markerRotation: .zero
        )
        let transform = LoadingScreenScene.modelTransform(pose, aspectRatio: 32.0 / 9.0)
        #expect(Self.close(Self.axis(transform, 0), [0.5, 0, 0]))
        #expect(Self.axis(transform, 3) == [5, 0, -10])
    }

    @Test func threeFixedLightsOverBlackOnlyTheFirstCasts() {
        let lights = LoadingScreenScene.lights
        #expect(lights.map(\.castsShadows) == [true, false, false])
        #expect(Self.close(lights[0].color, SIMD3(0.96, 0.96, 0.82) * 1.6))
        #expect(lights.map(\.radius) == [1500, 1024, 1024])
        let lighting = LoadingScreenScene.lighting
        #expect(lighting.ambientColor == .zero)
        #expect(lighting.directionalColor == .zero)
        #expect(lighting.directionalAmbient.positiveZ == .zero)
        #expect(lighting.fog == nil)
    }
}
