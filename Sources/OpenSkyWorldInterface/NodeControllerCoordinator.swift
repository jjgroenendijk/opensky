import OpenSkyFormatsMesh
import OpenSkyRendering
public import simd

/// One node of a running mesh, for `game state nodes`.
nonisolated public struct NodeControllerNodeRow: Equatable, Sendable {
    public let name: String
    /// Translation in the mesh's own space.
    public let translation: SIMD3<Float>
    public let rotation: simd_quatf
    public let controllers: [String]
    public let isActive: Bool
    public let isFrozen: Bool

    public init(
        name: String,
        translation: SIMD3<Float>,
        rotation: simd_quatf,
        controllers: [String],
        isActive: Bool,
        isFrozen: Bool
    ) {
        self.name = name
        self.translation = translation
        self.rotation = rotation
        self.controllers = controllers
        self.isActive = isActive
        self.isFrozen = isFrozen
    }
}
