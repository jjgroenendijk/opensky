public import OpenSkyCells
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyRendering

/// What the parts of `LoadingScreenWorldAdapter` share between frames.
@MainActor
public final class LoadingScreenPartState {
    var meshes: MeshLibrary?
    var failedModels: Set<String> = []
    /// The tip the movie shows; nil while no movie was asked for.
    var movieText: String?
    var movieFadedOut = false
    var cameraPaths: AssetLoader<String, NIFCameraTrack>?
    /// The app sees that a cell scene is a `CellScenePort`; the menu adapters do not.
    public var bringFollowers: ((CellScene) -> Void)?

    public init() {}
}
