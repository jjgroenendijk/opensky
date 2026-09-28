// Render debug views and layer isolation (issue #144): the two dev-shell view
// filters that let a visual bug be bisected instead of stared at.
//
// Both are deliberately transient. Unlike `ShadowQuality`, neither persists
// across launches: a session that starts in wireframe, or with the terrain
// switched off, reads as a rendering bug rather than as a control someone left
// on, and the whole point of the pair is to tell those two apart.
//
// The composition rule between a layer mask and the subsystem enables the
// renderer already carries is stated once, on `RenderLayerPolicy`, and folded
// exactly once per frame.

import Foundation
import OpenSkyShaderTypes

/// One scene role a draw can belong to. The renderer's filter is a mask over
/// these rather than one more boolean per subsystem, because `Renderer` already
/// carries `grassEnabled`, `particlesEnabled` and friends and a parallel set of
/// switches would be two competing controls for the same pixels.
///
/// Raw values are the shader contract: they match `RenderLayerBit` in
/// `ShaderTypes.h` bit for bit, and `RenderDebugStateTests` pins them.
nonisolated struct RenderLayer: OptionSet, Hashable, Sendable {
    let rawValue: UInt32

    /// Ordinary cell-owned world geometry: the default role, which is what
    /// keeps every existing `RenderPlacement` construction site unchanged.
    static let statics = RenderLayer(rawValue: 1 << 0)
    /// Actors and the player's own rig, from `ActorAssembly`.
    static let actors = RenderLayer(rawValue: 1 << 1)
    /// Distant LOD blocks and tree billboards.
    static let distantLOD = RenderLayer(rawValue: 1 << 2)
    static let terrain = RenderLayer(rawValue: 1 << 3)
    static let water = RenderLayer(rawValue: 1 << 4)
    static let sky = RenderLayer(rawValue: 1 << 5)
    static let grass = RenderLayer(rawValue: 1 << 6)
    /// Cell particle systems and precipitation, which share one encode path.
    static let particles = RenderLayer(rawValue: 1 << 7)

    /// Every layer on: the default, and the only mask a shipping frame uses.
    static let all: RenderLayer = [
        .statics, .actors, .distantLOD, .terrain, .water, .sky, .grass, .particles
    ]

    /// Stable presentation order for the panel checkboxes and the readout.
    /// Ordering by raw value would be equally stable but would put the sky
    /// between water and grass; this groups geometry before atmosphere.
    static let ordered: [RenderLayer] = [
        .statics, .actors, .distantLOD, .terrain, .grass, .water, .sky, .particles
    ]

    var title: String {
        switch self {
        case .statics: "Statics"
        case .actors: "Actors"
        case .distantLOD: "Distant LOD"
        case .terrain: "Terrain"
        case .water: "Water"
        case .sky: "Sky"
        case .grass: "Grass"
        case .particles: "Particles"
        default: "Multiple"
        }
    }

    /// The layer's part of its checkbox accessibility identifier. Spelled out
    /// rather than derived from `title`, because these are the UI-test API and
    /// a wording change to a label must not silently rename one.
    var identifierFragment: String {
        switch self {
        case .statics: "Statics"
        case .actors: "Actors"
        case .distantLOD: "DistantLOD"
        case .terrain: "Terrain"
        case .water: "Water"
        case .sky: "Sky"
        case .grass: "Grass"
        case .particles: "Particles"
        default: "Multiple"
        }
    }

    /// The one layer this mask isolates, or nil when it holds none or several.
    ///
    /// Solo is derived rather than stored precisely so that it cannot drift out
    /// of step with the per-layer toggles: unchecking a second layer by hand is
    /// the same act as pressing solo on the first.
    var soloedLayer: RenderLayer? {
        rawValue.nonzeroBitCount == 1 ? self : nil
    }
}

/// Which channel the scene pass writes instead of the shaded surface. Mirrors
/// `DebugViewMode` in `ShaderTypes.h`; `RenderDebugStateTests` pins the raw
/// values so a shader/Swift drift fails a test rather than showing up as a
/// wrong colour on screen.
nonisolated enum RenderDebugMode: UInt32, CaseIterable, Sendable {
    case off = 0
    case wireframe = 1
    case worldNormals = 2
    case textureCoordinates = 3
    case mipLevel = 4
    case shadowCascade = 5
    case layerCategory = 6

    var title: String {
        switch self {
        case .off: "Off"
        case .wireframe: "Wireframe"
        case .worldNormals: "World normals"
        case .textureCoordinates: "Texture coordinates"
        case .mipLevel: "Mip level"
        case .shadowCascade: "Shadow cascade"
        case .layerCategory: "Layer category"
        }
    }
}

/// The renderer's whole debug-view state: which channel the scene pass writes
/// and which layers it draws at all.
nonisolated struct RenderDebugState: Equatable, Sendable {
    var mode = RenderDebugMode.off
    var layers = RenderLayer.all

    /// What a shipping frame renders, and what an offscreen frame falls back to.
    static let production = RenderDebugState()

    var isDefault: Bool {
        self == .production
    }

    /// True while a debug pipeline is bound, which is also what decides whether
    /// the frame is safe to screenshot as engine output.
    var isDebugViewActive: Bool {
        mode != .off
    }

    var soloedLayer: RenderLayer? {
        layers.soloedLayer
    }
}

/// The composition rule between the two kinds of switch that reach the same
/// pixels, folded exactly once per frame and doing no GPU work.
///
/// A subsystem enable (`grassEnabled`, `particlesEnabled`,
/// `precipitationEnabled`) is the *feature* switch: semantic, persisted, owned
/// by its own panel section. The layer mask is the *view* filter: transient,
/// never persisted, dev-only. Effective visibility is the AND of the two, so
/// neither control can silently override the other.
nonisolated enum RenderLayerPolicy {
    static func effective(
        mask: RenderLayer,
        grassEnabled: Bool,
        particlesEnabled: Bool,
        precipitationEnabled: Bool
    ) -> RenderLayer {
        var result = mask
        if !grassEnabled {
            result.remove(.grass)
        }
        // Cell particles and precipitation share the `.particles` layer and the
        // same encode path, so the layer survives while either source is on;
        // each source is still ANDed with its own enable at its draw site.
        if !particlesEnabled, !precipitationEnabled {
            result.remove(.particles)
        }
        return result
    }
}

extension Renderer {
    /// This frame's layer mask after the feature switches have been folded in.
    /// Read by both the scene pass and the shadow pass, so hiding statics also
    /// removes the shadows they were casting — a mask that hid the geometry and
    /// kept its shadow would be actively misleading.
    var effectiveRenderLayers: RenderLayer {
        RenderLayerPolicy.effective(
            mask: renderDebug.layers,
            grassEnabled: grassEnabled,
            particlesEnabled: particlesEnabled,
            precipitationEnabled: precipitationEnabled
        )
    }

    /// Whether the scene pass binds the debug pipelines this frame.
    var isRenderDebugActive: Bool {
        renderDebug.isDebugViewActive
    }

    /// Isolates one layer, or restores all of them when it is already the only
    /// one drawn — the panel's solo button toggles rather than latches.
    func soloRenderLayer(_ layer: RenderLayer) {
        renderDebug.layers = renderDebug.soloedLayer == layer ? .all : layer
    }
}
