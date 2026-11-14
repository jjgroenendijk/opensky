// The joined draw-group list of a frame: kept while its sources stay the same,
// joined again when one changes, and shared when only one source has groups.

import Metal
@testable import OpenSkyFormatsCore
@testable import OpenSkyRendering
@testable import OpenSkyRenderResources
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.gpu), .unlessPlanSkips(.gpu))
struct JoinedDrawGroupsTests {
    private static let device = MTLCreateSystemDefaultDevice()

    private static var hasDevice: Bool {
        device != nil
    }

    private static func scene(boxes: Int, device: any MTLDevice) throws -> RenderScene {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false
        )
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        let material = Material(
            diffuseTexture: "texture", normalTexture: nil, uvOffset: .zero, uvScale: SIMD2(1, 1),
            alpha: 1, glossiness: 80, specularColor: SIMD3(1, 1, 1), specularStrength: 0,
            doubleSided: false, alphaBlend: false, alphaTestThreshold: nil
        )
        // One model per box, so each box is its own group.
        let placements = try (0 ..< boxes).map { index in
            let model = Model(
                meshes: [DemoScene.boxMesh(halfWidth: 8, halfDepth: 8, height: 8)],
                materials: [material],
                skippedShapeCount: 0
            )
            return try RenderPlacement(
                model: RenderModel(device: device, model: model) { _, _ in texture },
                transform: MatrixMath.translation(SIMD3(Float(index) * 40, 0, 0))
            )
        }
        return RenderScene(instances: placements)
    }

    /// The address of the list's storage, as an integer, so equal storage compares equal.
    private static func base(_ groups: [DrawGroup]) -> UInt? {
        groups.withUnsafeBufferPointer { buffer in
            unsafe buffer.baseAddress.map { UInt(bitPattern: $0) }
        }
    }

    @Test(.enabled(if: Self.hasDevice))
    func unchangedSourcesKeepTheJoinedListAndAChangeJoinsAgain() throws {
        let device = try #require(Self.device)
        let world = try Self.scene(boxes: 3, device: device)
        let effects = try Self.scene(boxes: 2, device: device)
        var joined = JoinedDrawGroups()

        joined.refresh([world.opaque, [], effects.opaque])
        let first = Self.base(joined.groups)
        #expect(joined.groups.count == 5)
        joined.refresh([world.opaque, [], effects.opaque])
        #expect(Self.base(joined.groups) == first)

        let fewer = try Self.scene(boxes: 1, device: device)
        joined.refresh([world.opaque, [], fewer.opaque])
        #expect(joined.groups.count == 4)
        #expect(joined.groups.last?.mesh === fewer.opaque.first?.mesh)
    }

    @Test(.enabled(if: Self.hasDevice))
    func aSingleNonEmptySourceSharesItsStorage() throws {
        let device = try #require(Self.device)
        let world = try Self.scene(boxes: 2, device: device)
        var joined = JoinedDrawGroups()

        joined.refresh([world.opaque, [], []])

        #expect(Self.base(joined.groups) == Self.base(world.opaque))
        joined.refresh([[], []])
        #expect(joined.groups.isEmpty)
    }
}
