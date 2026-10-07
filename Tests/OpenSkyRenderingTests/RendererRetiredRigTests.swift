// A scene swap retires the old scene's GPU allocations. The player's rigs share
// meshes and textures with the cell's actors, so a shared allocation must stay
// resident while a rig still draws it. Skips without Metal 4.

import EngineTesting
import Metal
@testable import OpenSkyFormatsCore
@testable import OpenSkyRendering
import simd
import TagsTesting
import Testing

@Suite(.tags(.gpu))
struct RendererRetiredRigTests {
    @Test(.enabled(if: OffscreenRendererFixture.hasMetal4Device))
    @MainActor
    func aRetiredSceneKeepsTheAllocationsARigShares() throws {
        let device = try #require(OffscreenRendererFixture.device)
        let shared = try Self.crate(device: device)
        let renderer = try OffscreenRendererFixture.makeRenderer(
            device: device, width: 64, height: 64,
            scene: RenderScene(instances: [shared]),
            shaderLibrary: ShaderLibraryFixture.library(device: device)
        )
        let driver = RigOnlyFrameDriver(rig: StaticRig(render: RenderScene(instances: [shared])))
        renderer.frameDriver = driver
        _ = try renderer.renderOffscreen(width: 64, height: 64)

        try renderer.setScene(RenderScene(instances: []))
        _ = try renderer.renderOffscreen(width: 64, height: 64)
        _ = try renderer.renderOffscreen(width: 64, height: 64)

        let rigAllocations = driver.rig.render.residencyAllocations
        #expect(!rigAllocations.isEmpty)
        for allocation in rigAllocations {
            #expect(renderer.residencySet.containsAllocation(allocation))
        }
    }

    private static func crate(device: MTLDevice) throws -> RenderPlacement {
        let texture = try OffscreenRendererFixture.solidTexture(device: device)
        let model = Model(
            meshes: [DemoScene.boxMesh(halfWidth: 32, halfDepth: 32, height: 64)],
            materials: [Material.fallback],
            skippedShapeCount: 0
        )
        let render = try RenderModel(device: device, model: model) { _, _ in texture }
        return RenderPlacement(
            model: render, transform: matrix_identity_float4x4,
            bounds: ModelBounds.containing(model: model)
        )
    }
}

@MainActor
private final class StaticRig: RenderRig {
    let render: RenderScene

    init(render: RenderScene) {
        self.render = render
    }

    func publishAnimation(enabled _: Bool) -> Int {
        0
    }
}

@MainActor
private final class RigOnlyFrameDriver: RenderFrameDriver {
    let rig: StaticRig
    var timeOfDay = Renderer.defaultTimeOfDay

    init(rig: StaticRig) {
        self.rig = rig
    }

    var wind: WindState {
        .calm
    }

    var projectionFOVYRadians: Float {
        FirstPersonCamera.defaultFOVYRadians
    }

    var rigVisibility: PlayerRigVisibility {
        .resolve(mode: .fly, hasBody: true, hasArms: false)
    }

    var playerBodyRig: (any RenderRig)? {
        rig
    }

    var firstPersonRig: (any RenderRig)? {
        nil
    }

    var lastScriptUpdateMS: Double {
        0
    }

    var lastAudioUpdateMS: Double {
        0
    }

    func prepareLiveFrame() {}
    func finishLiveFrame() {}
    func updateWorldSim(deltaTime _: Float) {}
    func updateWeather(deltaTime _: Float) {}
    func updateAudio(deltaTime _: Float) {}
    func didReplaceCamera(_: SceneCamera) {}
}
