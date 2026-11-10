// Surface shading: switch each lit-mesh term and count the
// draws that use it.

public import OpenSkyGameData
public import OpenSkyRenderResources

nonisolated extension SurfaceShadingSetting {
    public var term: SurfaceShadingTerm {
        switch self {
        case .normalMaps: .normalMaps
        case .specular: .specular
        case .glow: .glow
        case .softAndRimLight: .softAndRimLight
        case .backLight: .backLight
        case .faceTint: .faceTint
        case .tintColor: .tintColor
        case .reflections: .reflections
        case .parallax: .parallax
        case .vertexColorGamma: .vertexColorGamma
        case .baseAmbient: .baseAmbient
        case .hairLighting: .hairLighting
        case .sparkle: .sparkle
        case .landscapeNoise: .landscapeNoise
        case .materialDrawState: .materialDrawState
        case .refraction: .refraction
        case .softEffects: .softEffects
        case .effectLighting: .effectLighting
        }
    }
}

extension PlayerSettingsStore {
    /// The game's `bToggleSparkles` turns the sparkle term off with its own switch.
    var surfaceShadingTerms: SurfaceShadingTerm {
        var terms: SurfaceShadingTerm = []
        for setting in SurfaceShadingSetting.allCases where bool(setting.id) {
            terms.insert(setting.term)
        }
        if !bool(.snowSparkles) {
            terms.remove(.sparkle)
        }
        return terms
    }
}
