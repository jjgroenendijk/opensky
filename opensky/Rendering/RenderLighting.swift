// Renderer-facing cell lighting: resolved ambient/directional/fog plus
// placed point lights. No plugin types cross into shader/renderer code.

import simd

nonisolated struct FogParameters: Equatable {
    let nearColor: SIMD3<Float>
    let farColor: SIMD3<Float>
    let nearDistance: Float
    let farDistance: Float
    let power: Float
    let maximum: Float
}

nonisolated struct RenderLighting: Equatable {
    let ambientColor: SIMD3<Float>
    let directionalAmbient: DirectionalAmbientColors
    /// Unit vector: direction the cell directional light travels.
    let directionalDirection: SIMD3<Float>
    let directionalColor: SIMD3<Float>
    let fog: FogParameters?
}

nonisolated struct RenderPointLight: Equatable {
    let position: SIMD3<Float>
    let radius: Float
    let color: SIMD3<Float>
    let falloffExponent: Float
}
