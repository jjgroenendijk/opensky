// The one SWF layer that the HUD, the menus, and the UI Lab take turns to own.

import OpenSkyGameData
import OpenSkyRendering

/// What a menu coordinator reads from the app. nil while Metal 4 is unavailable.
public protocol SWFLayerWorld: AnyObject {
    var renderer: Renderer? { get }
}

/// Builds the movie loader once. Listing `interface\*.swf` walks every archive
/// index, and the 2 Hz panel readout must never repeat that walk.
public final class SWFMovieSource {
    /// Set by the app; nil without game data.
    public var factory: (() -> SWFMovieLoader)?
    private var cachedLoader: SWFMovieLoader?
    private var loaderResolved = false
    private var cachedPaths: [String]?

    public init(factory: (() -> SWFMovieLoader)? = nil) {
        self.factory = factory
    }

    public var loader: SWFMovieLoader? {
        if !loaderResolved {
            cachedLoader = factory?()
            loaderResolved = true
        }
        return cachedLoader
    }

    public var moviePaths: [String] {
        if let cachedPaths {
            return cachedPaths
        }
        let paths = loader?.moviePaths() ?? []
        cachedPaths = paths
        return paths
    }
}
