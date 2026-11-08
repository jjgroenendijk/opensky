public import OpenSkyGameData
public import OpenSkyMenusInterface

/// What the world adapters use of `SWFMovieSource`.
public protocol SWFMovieSourcePort: AnyObject, MenuMovieLoading {
    var fileSystem: (any GameFileSource)? { get }
}
