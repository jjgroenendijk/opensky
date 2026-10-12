// The lit-mesh terms a frame draws, in the groups the sidebar and the launcher
// switch together. Mirrors the `ShadingTerm` bits in ShaderTypes.h.

import OpenSkyShaderTypes

nonisolated public struct SurfaceShadingTerm: OptionSet, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    private init(_ terms: ShadingTerm...) {
        rawValue = terms.reduce(0) { $0 | UInt32($1.rawValue) }
    }

    public static let normalMaps = Self(.normalMap, .modelSpaceNormals)
    public static let specular = Self(.specular, .specularMap)
    public static let glow = Self(.emissive, .glowMap)
    public static let softAndRimLight = Self(.softLighting, .rimLighting)
    public static let backLight = Self(.backLighting)
    public static let faceTint = Self(.faceTint, .faceDetail)
    public static let tintColor = Self(.tintColor)
    public static let reflections = Self(.environment, .environmentMask)
    public static let parallax = Self(.parallax, .multiLayer)
    public static let vertexColorGamma = Self(.vertexColorGamma)
    public static let baseAmbient = Self(.baseAmbient)

    public static let all: Self = [
        .normalMaps, .specular, .glow, .softAndRimLight, .backLight, .faceTint, .tintColor,
        .reflections, .parallax, .vertexColorGamma, .baseAmbient
    ]
}
