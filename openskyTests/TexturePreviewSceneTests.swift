// Texture-preview quad math: geometry, winding toward the camera, DDS UV
// orientation, flat-light camera framing. Pure values — no GPU needed.

@testable import opensky
import simd
import Testing

struct TexturePreviewSceneTests {
    @Test func quadFollowsTheTextureAspect() throws {
        let model = TexturePreviewScene.model(textureKey: "textures\\t.dds", aspect: 2)
        let mesh = try #require(model.meshes.first)
        #expect(model.meshes.count == 1)
        #expect(mesh.positions.count == 4)
        #expect(mesh.indices == [0, 1, 2, 0, 2, 3])
        let width = mesh.positions[1].x - mesh.positions[0].x
        let height = mesh.positions[2].z - mesh.positions[1].z
        #expect(abs(width - 2 * height) < 0.001)
        #expect(abs(height - TexturePreviewScene.quadHeight) < 0.001)
    }

    @Test func trianglesWindTowardTheCamera() throws {
        let model = TexturePreviewScene.model(textureKey: "textures\\t.dds", aspect: 1)
        let mesh = try #require(model.meshes.first)
        // CCW toward the -Y camera: right-hand normal of each triangle
        // points down -Y (the renderer fronts counter-clockwise faces).
        for triangle in stride(from: 0, to: mesh.indices.count, by: 3) {
            let first = mesh.positions[Int(mesh.indices[triangle])]
            let second = mesh.positions[Int(mesh.indices[triangle + 1])]
            let third = mesh.positions[Int(mesh.indices[triangle + 2])]
            let normal = simd_cross(second - first, third - first)
            #expect(normal.y < 0, "triangle winds away from the camera")
        }
    }

    @Test func uvTopRowSitsAtPlusZ() throws {
        let model = TexturePreviewScene.model(textureKey: "textures\\t.dds", aspect: 1)
        let mesh = try #require(model.meshes.first)
        // DDS rows start at the image top -> v=0 belongs to the +Z corners.
        for index in mesh.positions.indices {
            let expectedV: Float = mesh.positions[index].z > 0 ? 0 : 1
            #expect(mesh.uvs[index].y == expectedV)
        }
    }

    @Test func cameraIsHeadOnWithFlatLight() {
        let camera = TexturePreviewScene.camera()
        #expect(camera.target == .zero)
        #expect(camera.eye.x == 0)
        #expect(camera.eye.z == 0)
        #expect(camera.eye.y < 0)
        // Distance fits the quad height into the renderer's 65-deg fov.
        let halfHeight = TexturePreviewScene.quadHeight / 2
        let expected = halfHeight / tanf(MatrixMath.radians(fromDegrees: 65) / 2) * 1.02
        #expect(abs(-camera.eye.y - expected) < 0.01)
        // Black sun + white ambient -> fragment output == sampled texel.
        #expect(camera.sunColor == .zero)
        #expect(camera.ambientColor == SIMD3<Float>(1, 1, 1))
    }
}
