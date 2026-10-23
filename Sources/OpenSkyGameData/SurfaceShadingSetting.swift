// One player setting per lit-mesh shading term group, so a player can compare a
// surface with and without each term. docs/rendering/surface-shading.md.

nonisolated public enum SurfaceShadingSetting: String, CaseIterable, Sendable {
    case normalMaps
    case specular
    case glow
    case softAndRimLight
    case backLight
    case faceTint
    case tintColor
    case reflections
    case parallax
    case vertexColorGamma
    case baseAmbient
    case hairLighting
    case sparkle
    case landscapeNoise
    case materialDrawState
    case refraction
    case softEffects
    case effectLighting

    public var id: PlayerSettingID {
        PlayerSettingID("rendering.shading.\(rawValue)")
    }

    /// `NormalMaps` for `.normalMaps`, for control identifiers.
    public var controlName: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    public var title: String {
        switch self {
        case .normalMaps: "Surface normal maps"
        case .specular: "Specular highlights"
        case .glow: "Glow and emissive colour"
        case .softAndRimLight: "Soft and rim light"
        case .backLight: "Back light"
        case .faceTint: "Face tint and detail"
        case .tintColor: "Hair and skin tint colour"
        case .reflections: "Environment reflections"
        case .parallax: "Parallax and layered surfaces"
        case .vertexColorGamma: "Vertex colours in gamma space"
        case .baseAmbient: "Base ambient light"
        case .hairLighting: "Hair lighting"
        case .sparkle: "Snow and ice sparkle"
        case .landscapeNoise: "Distant terrain noise"
        case .materialDrawState: "Material depth and decal flags"
        case .refraction: "Refraction and heat haze"
        case .softEffects: "Soft effect edges"
        case .effectLighting: "Scene light on effects"
        }
    }

    public var toolTip: String {
        switch self {
        case .normalMaps: "Bend the lighting of objects and actors by their normal maps"
        case .specular: "Shiny highlights from the sun and nearby lights"
        case .glow: "Glowing parts such as lit windows and embers"
        case .softAndRimLight: "Light that wraps around skin and edges facing away"
        case .backLight: "Light that shines through thin surfaces such as leaves"
        case .faceTint: "Each face's own colouring and its skin detail map"
        case .tintColor: "The hair colour and skin colour a model stores"
        case .reflections: "Reflections of the surroundings on metal, glass, and eyes"
        case .parallax: "Height-mapped surfaces and the layer under ice and glass"
        case .vertexColorGamma: "Treat baked vertex colours as gamma values, as the game does"
        case .baseAmbient: "Add the single ambient colour on top of the six-axis ambient"
        case .hairLighting: "Soft, capped light on hair and highlights along its strands"
        case .sparkle: "Small glints on snow and ice surfaces"
        case .landscapeNoise: "A noise texture that breaks up the colour of distant land"
        case .materialDrawState:
            "Each model's own depth test, depth write, decal offset, and dither fade"
        case .refraction: "Glass-like shapes and the heat over fires that bend the view behind"
        case .softEffects: "Smoke, mist, and fire fade out where they meet the ground and walls"
        case .effectLighting: "Smoke, mist, and dust take the colour of the light around them"
        }
    }

    static var definitions: [PlayerSettingDefinition] {
        allCases.map {
            PlayerSettingDefinition(
                id: $0.id, group: .opensky, kind: .toggle, title: $0.title,
                defaultValue: 1, isApplied: true
            )
        }
    }
}
