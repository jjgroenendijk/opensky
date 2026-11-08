public import OpenSkyFormatsESM
public import OpenSkyGameData

/// What the world adapters use of `LoadingScreenSession`.
public protocol LoadingScreenSessionPort {
    var screen: ResolvedRecord<LoadScreen>? { get }
    var turnDegrees: Float { get }
}
