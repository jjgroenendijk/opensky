/// One mesh's morph targets, as face playback drives them. The GPU buffer behind it
/// lives in a render module, which this module sits below.
public protocol FaceMorphWeightTarget: AnyObject, Sendable {
    nonisolated var targetNames: [String] { get }
    nonisolated func update(weights: [String: Float])
}
