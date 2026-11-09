import Metal
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsMesh
@testable import OpenSkyPlayer
@testable import OpenSkyRenderResources
import OpenSkyTagsTesting
import OpenSkyWorldInterface
import simd
import Testing

@Suite(.tags(.gpu), .unlessPlanSkips(.gpu))
struct FaceMorphBufferWeightTargetTests {
    /// Buffers only, so any Metal device will do, as on the CI runners.
    private static let device = MTLCreateSystemDefaultDevice()

    private static var hasDevice: Bool {
        device != nil
    }

    private static func buffer(device: any MTLDevice) throws -> FaceMorphBuffer {
        let positions = [SIMD3<Float>(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)]
        let mesh = try RenderMesh(device: device, mesh: Mesh(
            name: "head", transform: matrix_identity_float4x4, positions: positions,
            normals: [], tangents: [], bitangents: [], uvs: [], colors: [],
            indices: [0, 1, 2], materialSlot: 0
        ))
        let tri = TRIFile(
            baseVertices: positions,
            triangles: [TRITriangle(vertices: SIMD3(0, 1, 2))],
            morphTargets: ["Blink", "Smile"].map {
                TRIMorphTarget(name: $0, scale: 1, deltas: Array(repeating: .zero, count: 3))
            }
        )
        return try FaceMorphBuffer(device: device, tri: tri, mesh: mesh)
    }

    @Test(.enabled(if: Self.hasDevice))
    func weightTargetNamesTheMorphTargets() throws {
        let buffer = try Self.buffer(device: #require(Self.device))
        #expect(buffer.targetNames == ["Blink", "Smile"])
    }

    @Test(.enabled(if: Self.hasDevice))
    func playbackHandsBackItsGPUBuffers() throws {
        let buffer = try Self.buffer(device: #require(Self.device))
        let key = ObjectIdentifier(buffer)
        let playback = FaceMorphPlayback(
            actor: FormID(0x14), bindings: [key: buffer], pairedPaths: [], misses: []
        )
        #expect(playback.renderBuffers[key] === buffer)
        #expect(playback.targetNames == ["Blink", "Smile"])
    }
}
