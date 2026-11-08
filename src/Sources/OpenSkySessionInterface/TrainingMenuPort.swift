public import OpenSkyFormatsESM

/// What the world adapters use of `TrainingMenuCoordinator`.
public protocol TrainingMenuPort: AnyObject {
    @discardableResult func open(trainer: ReferenceKey) -> Bool
}
