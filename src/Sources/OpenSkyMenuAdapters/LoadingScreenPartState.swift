public import OpenSkyCells
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyRendering
import simd

/// What the parts of `LoadingScreenWorldAdapter` share between frames.
@MainActor
public final class LoadingScreenPartState {
    var meshes: MeshLibrary?
    var failedModels: Set<String> = []
    /// The tip the movie shows; nil while no movie was asked for.
    var movieText: String?
    var movieFadedOut = false
    /// Tip requests the movie made for the current screen.
    var tipRequests = 0
    /// The tip shown now; a later request from the movie draws another.
    var shownTip: String?
    /// Another random tip from the screens that may show.
    public var nextTip: (() -> String?)?
    var cameraPaths: AssetLoader<String, LoadingCameraPath>?
    /// Each screen model's inventory marker turn, read off the main actor.
    var modelMarkers: AssetLoader<String, LoadingModelMarker>?
    /// The mist of the cover that shows, kept so its particles run on.
    var mist: LoadingMist?
    /// The app sees that a cell scene is a `CellScenePort`; the menu adapters do not.
    public var bringFollowers: ((CellScene) -> Void)?

    public init() {}
}

/// A loading screen model's inventory marker turn, radians per axis; nil without one.
nonisolated struct LoadingModelMarker: Sendable {
    let rotation: SIMD3<Float>?
}

/// The mist behind a loading screen model, built once per cover.
struct LoadingMist {
    let placements: [RenderPlacement]
    let particles: [ParticlePlayback]
}
