/// The game's surface shading switches that change what a frame feeds the shaders.
nonisolated public struct SurfaceFeatureSwitches: Equatable, Sendable {
    /// `bIBLFEnable`: specular surfaces reflect the six-axis ambient light.
    public var imageBasedLighting = false
    /// `bEnableImprovedSnow`: LTEX snow ground takes the snow shading.
    public var improvedSnow = false
    /// `bEnableProjecteUVDiffuseNormals`: directional materials draw their textures.
    public var projectedTextures = false

    public init() {}
}
