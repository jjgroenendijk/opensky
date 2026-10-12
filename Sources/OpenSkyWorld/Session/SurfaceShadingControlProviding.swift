// World > Environment > Surface Shading: switch each lit-mesh term and count the
// draws that use it.

import OpenSkyGameData
import OpenSkyRendering

@MainActor
public protocol SurfaceShadingControlProviding: AnyObject {
    func isShadingEnabled(_ setting: SurfaceShadingSetting) -> Bool
    func setShading(_ setting: SurfaceShadingSetting, enabled: Bool)
    /// Scene draws whose material has any term of `setting`.
    func shadingDrawCount(_ setting: SurfaceShadingSetting) -> Int
}

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

extension WorldRenderControls: SurfaceShadingControlProviding {
    public func isShadingEnabled(_ setting: SurfaceShadingSetting) -> Bool {
        renderer.map { $0.shadingTerms.isSuperset(of: setting.term) }
            ?? world?.playerSettingsStore.bool(setting.id) ?? true
    }

    public func setShading(_ setting: SurfaceShadingSetting, enabled: Bool) {
        if enabled {
            renderer?.shadingTerms.formUnion(setting.term)
        } else {
            renderer?.shadingTerms.subtract(setting.term)
        }
        world?.playerSettingsStore.set(setting.id, to: enabled ? 1 : 0)
    }

    public func shadingDrawCount(_ setting: SurfaceShadingSetting) -> Int {
        guard let scene = renderer?.scene else { return 0 }
        return (scene.opaque + scene.alphaTested).count {
            $0.material.surface.flags & setting.term.rawValue != 0
        }
    }
}
