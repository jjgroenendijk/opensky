// Render debug views and layer isolation, to bisect a visual bug. Both are transient:
// a session that starts in wireframe would look like a rendering bug. The rule that
// combines the layer mask with subsystem switches is `RenderLayerPolicy`.

import Foundation
import OpenSkyShaderTypes

/// One scene role a draw belongs to. A mask over these, not more booleans beside
/// `grassEnabled` and friends. Raw values match `RenderLayerBit` in `ShaderTypes.h`,
/// pinned by `RenderDebugStateTests`.
nonisolated public struct RenderLayer: OptionSet, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// Ordinary cell-owned world geometry: the default role, which is what
    /// keeps every existing `RenderPlacement` construction site unchanged.
    public static let statics = RenderLayer(rawValue: 1 << 0)
    /// Actors and the player's own rig, from `ActorAssembly`.
    public static let actors = RenderLayer(rawValue: 1 << 1)
    /// Distant LOD blocks and tree billboards.
    public static let distantLOD = RenderLayer(rawValue: 1 << 2)
    public static let terrain = RenderLayer(rawValue: 1 << 3)
    public static let water = RenderLayer(rawValue: 1 << 4)
    public static let sky = RenderLayer(rawValue: 1 << 5)
    public static let grass = RenderLayer(rawValue: 1 << 6)
    /// Cell particle systems and precipitation, which share one encode path.
    public static let particles = RenderLayer(rawValue: 1 << 7)
    /// The loading screen's object. Never in `all`: it draws alone, in place of the world.
    public static let loadingCover = RenderLayer(rawValue: 1 << 8)

    /// Every layer on: the default, and the only mask a shipping frame uses.
    public static let all: RenderLayer = [
        .statics, .actors, .distantLOD, .terrain, .water, .sky, .grass, .particles
    ]

    /// Stable presentation order for the panel checkboxes and the readout.
    /// Ordering by raw value would be equally stable but would put the sky
    /// between water and grass; this groups geometry before atmosphere.
    public static let ordered: [RenderLayer] = [
        .statics, .actors, .distantLOD, .terrain, .grass, .water, .sky, .particles
    ]

    public var title: String {
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
    public var identifierFragment: String {
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
    public var soloedLayer: RenderLayer? {
        rawValue.nonzeroBitCount == 1 ? self : nil
    }
}

/// Which channel the scene pass writes instead of the shaded surface. Mirrors
/// `DebugViewMode` in `ShaderTypes.h`; `RenderDebugStateTests` pins the raw
/// values so a shader/Swift drift fails a test rather than showing up as a
/// wrong colour on screen.
nonisolated public enum RenderDebugMode: UInt32, CaseIterable, Sendable {
    case off = 0
    case wireframe = 1
    case worldNormals = 2
    case textureCoordinates = 3
    case mipLevel = 4
    case shadowCascade = 5
    case layerCategory = 6

    public var title: String {
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
nonisolated public struct RenderDebugState: Equatable, Sendable {
    public var mode = RenderDebugMode.off
    public var layers = RenderLayer.all

    /// What a shipping frame renders, and what an offscreen frame falls back to.
    public static let production = RenderDebugState()

    public var isDefault: Bool {
        self == .production
    }

    /// True while a debug pipeline is bound, which is also what decides whether
    /// the frame is safe to screenshot as engine output.
    public var isDebugViewActive: Bool {
        mode != .off
    }

    public var soloedLayer: RenderLayer? {
        layers.soloedLayer
    }
}

/// Visibility is the AND of a subsystem switch (`grassEnabled`, persisted) and the
/// layer mask (transient, dev-only), folded once per frame, so neither overrides the other.
nonisolated public enum RenderLayerPolicy: Sendable {
    public static func effective(
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
    public var effectiveRenderLayers: RenderLayer {
        guard effects.loadingCover == nil else { return .loadingCover }
        return RenderLayerPolicy.effective(
            mask: renderDebug.layers,
            grassEnabled: grassEnabled,
            particlesEnabled: particlesEnabled,
            precipitationEnabled: precipitationEnabled
        )
    }

    /// Whether the scene pass binds the debug pipelines this frame.
    public var isRenderDebugActive: Bool {
        renderDebug.isDebugViewActive
    }

    /// Isolates one layer, or restores all of them when it is already the only
    /// one drawn — the panel's solo button toggles rather than latches.
    public func soloRenderLayer(_ layer: RenderLayer) {
        renderDebug.layers = renderDebug.soloedLayer == layer ? .all : layer
    }
}
