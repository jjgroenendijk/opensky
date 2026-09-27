// M7.4.1 precipitation math, roof occlusion, camera volume, shared Metal
// particle-pass evidence. Synthetic engine values only; no game assets.

import Metal
import MetalKit
@testable import opensky
import simd
import Testing

struct PrecipitationTests {
    @Test func weatherBlendSuppliesIntensityAndDarkensStormSky() {
        let clear = PrecipitationState.none
        let rain = PrecipitationState(.rainy)
        let snow = PrecipitationState(.snow)
        let middle = PrecipitationState.blend(clear, rain, 0.4)
        #expect(middle.rainIntensity == 0.4)
        #expect(middle.snowIntensity == 0)
        #expect(PrecipitationState.blend(rain, snow, 0.25)
            == PrecipitationState(rainIntensity: 0.75, snowIntensity: 0.25))

        let storm = resolved(precipitation: middle)
        let darkened = storm.applyingStormSkyDarkening()
        #expect(darkened.skyUpper.x < storm.skyUpper.x)
        #expect(darkened.skyLower.y < storm.skyLower.y)
        #expect(darkened.ambientColor == storm.ambientColor)
    }

    @Test func upwardRayFindsTriangleRoofOnlyAboveCamera() {
        let roof = StaticCollisionShape(
            reference: FormID(1),
            transform: matrix_identity_float4x4,
            geometry: .triangleSoup(
                vertices: [SIMD3(-10, -10, 20), SIMD3(10, -10, 20), SIMD3(0, 10, 20)],
                indices: [0, 1, 2]
            ),
            bounds: ModelBounds(min: SIMD3(-10, -10, 20), max: SIMD3(10, 10, 20))
        )
        let query: WalkController.CollisionQuery = { bounds in
            roof.bounds.overlaps(bounds) ? [roof] : []
        }
        #expect(PrecipitationRoofOcclusion.isOccluded(above: .zero, query: query))
        #expect(!PrecipitationRoofOcclusion.isOccluded(
            above: SIMD3(30, 0, 0), query: query
        ))
        #expect(!PrecipitationRoofOcclusion.isOccluded(
            above: .zero, maximumDistance: 10, query: query
        ))
    }

    @Test(.enabled(if: Self.device != nil))
    @MainActor
    func volumeFollowsCameraUsesWindAndStopsUnderRoof() throws {
        let device = try #require(Self.device)
        let volume = try PrecipitationVolume(device: device)
        for _ in 0 ..< 10 {
            volume.update(update(camera: SIMD3(10, 20, 30), state: .init(.rainy)))
        }
        #expect(volume.anchor == SIMD3(10, 20, 630))
        #expect(volume.snapshot.rainLiveCount > 0)
        #expect(volume.snapshot.snowLiveCount == 0)

        volume.update(update(camera: SIMD3(110, 220, 30), state: .init(.rainy)))
        #expect(volume.anchor == SIMD3(110, 220, 630))

        for _ in 0 ..< 10 {
            volume.update(update(camera: SIMD3(110, 220, 30), state: .init(.snow)))
        }
        #expect(volume.snapshot.snowLiveCount > 0)

        var roofed = update(camera: SIMD3(110, 220, 30), state: .init(.rainy))
        roofed = PrecipitationUpdate(
            cameraPosition: roofed.cameraPosition,
            state: roofed.state,
            wind: roofed.wind,
            deltaTime: roofed.deltaTime,
            exterior: true,
            enabled: true,
            collisionQuery: { _ in [Self.roof(at: SIMD3(110, 220, 100))] }
        )
        volume.update(roofed)
        #expect(volume.snapshot.roofOccluded)
        #expect(volume.snapshot.rainLiveCount == 0)
        #expect(volume.drawItems.isEmpty)
    }

    @Test(.enabled(if: Self.device != nil))
    @MainActor
    func rainVolumeChangesPixelsThroughSharedParticlePass() throws {
        let device = try #require(Self.device)
        let baseline = try RendererShadowTests.makeRenderer(device: device)
        let baselinePixels = try RendererShadowTests.readPixels(
            texture: baseline.renderOffscreen(
                width: RendererShadowTests.width,
                height: RendererShadowTests.height,
                animationTime: 0
            )
        )

        let rainy = try RendererShadowTests.makeRenderer(device: device)
        for _ in 0 ..< 15 {
            rainy.precipitation.update(update(
                camera: rainy.freeFlyCamera.position,
                state: .init(.rainy)
            ))
        }
        let rainyPixels = try RendererShadowTests.readPixels(
            texture: rainy.renderOffscreen(
                width: RendererShadowTests.width,
                height: RendererShadowTests.height,
                animationTime: 0
            )
        )
        let changed = baselinePixels.indices.reduce(0) {
            $0 + (baselinePixels[$1] == rainyPixels[$1] ? 0 : 1)
        }
        #expect(rainy.precipitation.snapshot.rainLiveCount > 20)
        #expect(changed > 100, "rain changed only \(changed) channels")

        rainy.particlesEnabled = false
        let worldParticlesOff = try RendererShadowTests.readPixels(
            texture: rainy.renderOffscreen(
                width: RendererShadowTests.width,
                height: RendererShadowTests.height,
                animationTime: 0
            )
        )
        #expect(worldParticlesOff == rainyPixels)

        rainy.precipitationEnabled = false
        let precipitationOff = try RendererShadowTests.readPixels(
            texture: rainy.renderOffscreen(
                width: RendererShadowTests.width,
                height: RendererShadowTests.height,
                animationTime: 0
            )
        )
        #expect(precipitationOff == baselinePixels)
    }
}

extension PrecipitationTests {
    fileprivate static let device: MTLDevice? = {
        guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4)
        else { return nil }
        return device
    }()

    private func update(
        camera: SIMD3<Float>,
        state: PrecipitationState
    ) -> PrecipitationUpdate {
        PrecipitationUpdate(
            cameraPosition: camera,
            state: state,
            wind: WindState(direction: SIMD2(1, 0), speed: 0.7, meanderRange: 10),
            deltaTime: 0.05,
            exterior: true,
            enabled: true,
            collisionQuery: { _ in [] }
        )
    }

    fileprivate static func roof(at center: SIMD3<Float>) -> StaticCollisionShape {
        StaticCollisionShape(
            reference: FormID(2),
            transform: MatrixMath.translation(center),
            geometry: .box(halfExtents: SIMD3(20, 20, 2)),
            bounds: ModelBounds(min: center - SIMD3(20, 20, 2), max: center + SIMD3(20, 20, 2))
        )
    }

    private func resolved(precipitation: PrecipitationState) -> ResolvedWeather {
        ResolvedWeather(
            skyUpper: .one,
            skyLower: .one,
            horizon: .one,
            sun: .one,
            sunGlare: .one,
            stars: .one,
            fogNearColor: .one,
            fogFarColor: .one,
            fogNearDistance: 0,
            fogFarDistance: 100,
            fogPower: 1,
            fogMaximum: 1,
            fogEnabled: true,
            sunlightColor: .one,
            ambientColor: .one,
            directionalAmbient: .black,
            wind: .calm,
            precipitation: precipitation
        )
    }
}
