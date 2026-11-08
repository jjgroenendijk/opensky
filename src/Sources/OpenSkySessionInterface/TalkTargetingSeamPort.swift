public import OpenSkyFormatsESM

/// What the world adapters use of `TalkTargetingSeam`.
public protocol TalkTargetingSeamPort {
    var speaker: ReferenceKey? { get }
}
