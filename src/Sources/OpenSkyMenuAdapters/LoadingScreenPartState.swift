public import OpenSkyFormatsMesh
public import OpenSkyGameData
import OpenSkyRendering

/// What the parts of `LoadingScreenWorldAdapter` share between frames.
@MainActor
public final class LoadingScreenPartState {
    var meshes: MeshLibrary?
    var failedModels: Set<String> = []
    /// The tip the movie shows; nil while no movie was asked for.
    public var movieText: String?
    public var movieFadedOut = false
    public var cameraPaths: AssetLoader<String, NIFCameraTrack>?

    public init() {}
}
