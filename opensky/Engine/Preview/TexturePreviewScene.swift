// Flat textured-quad scene for the DDS preview: the texture is stretched on
// a camera-facing quad lit with white ambient and no sun, so the offscreen
// frame reproduces the texels as the engine samples them (same TextureLoader
// upload, sampler and sRGB policy). AppKit- and GPU-free — model and camera
// are pure values, unit-tested; rendering reuses Renderer.renderOffscreen.

import simd

nonisolated enum TexturePreviewScene {
    /// Quad height in world units. At the framing distance below the quad
    /// sits far beyond the renderer's 10-unit near plane, so even extreme
    /// texture aspects never clip.
    static let quadHeight: Float = 1000

    /// Must match the renderer's projection fov (65 deg) so the framing
    /// distance below fills the frame vertically.
    private static let fovYRadians = MatrixMath.radians(fromDegrees: 65)

    /// Camera-facing quad in the X-Z plane (normal -Y, toward the camera),
    /// UV v=0 at the top (+Z) matching DDS row order, CCW winding as seen
    /// from the camera (renderer front face). Width follows the texture
    /// aspect so texels stay square.
    static func model(textureKey: String, aspect: Float) -> Model {
        let halfWidth = quadHeight * max(aspect, 0.001) / 2
        let halfHeight = quadHeight / 2
        let mesh = Mesh(
            name: "texture-preview-quad",
            transform: matrix_identity_float4x4,
            positions: [
                SIMD3(-halfWidth, 0, -halfHeight),
                SIMD3(halfWidth, 0, -halfHeight),
                SIMD3(halfWidth, 0, halfHeight),
                SIMD3(-halfWidth, 0, halfHeight)
            ],
            normals: Array(repeating: SIMD3(0, -1, 0), count: 4),
            tangents: [],
            bitangents: [],
            uvs: [SIMD2(0, 1), SIMD2(1, 1), SIMD2(1, 0), SIMD2(0, 0)],
            colors: [],
            indices: [0, 1, 2, 0, 2, 3],
            materialSlot: 0
        )
        let material = Material(
            diffuseTexture: textureKey,
            normalTexture: nil,
            uvOffset: .zero,
            uvScale: SIMD2(1, 1),
            alpha: 1,
            glossiness: 80,
            specularColor: SIMD3(1, 1, 1),
            specularStrength: 1,
            doubleSided: false,
            alphaBlend: false,
            alphaTestThreshold: nil
        )
        return Model(meshes: [mesh], materials: [material], skippedShapeCount: 0)
    }

    /// Head-on camera at the distance where the quad's height exactly fills
    /// the vertical fov (hair of margin). Black sun + white ambient -> the
    /// fragment shader outputs the sampled texel unchanged.
    static func camera() -> SceneCamera {
        let distance = quadHeight / 2 / tanf(fovYRadians / 2) * 1.02
        return SceneCamera(
            eye: SIMD3(0, -distance, 0),
            target: .zero,
            sunDirection: SIMD3(0, 1, 0),
            sunColor: .zero,
            ambientColor: SIMD3(1, 1, 1)
        )
    }
}
