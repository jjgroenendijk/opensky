public import OpenSkyMenusInterface

/// What the world adapters use of `LoadingScreenWorldAdapter`.
public protocol LoadingScreenWorldPort: AnyObject {
    func coverMove(to feet: SIMD3<Float>)
    var isMovieLoaded: Bool { get }
    func route(_ event: MenuInputEvent)
}
