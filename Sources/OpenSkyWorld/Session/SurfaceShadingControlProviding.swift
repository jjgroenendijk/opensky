// Surface shading: switch each lit-mesh term and count the
// draws that use it.

import OpenSkyGameData
import OpenSkyRendering

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

extension SurfaceShadingSetting {
    public static func terms(store: PlayerSettingsStore) -> SurfaceShadingTerm {
        allCases.reduce(into: []) { terms, setting in
            if store.bool(setting.id) {
                terms.insert(setting.term)
            }
        }
    }
}
