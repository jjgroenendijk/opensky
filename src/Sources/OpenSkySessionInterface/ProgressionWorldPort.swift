public import OpenSkyFormatsESM
public import OpenSkyProgressionInterface

/// What the world adapters use of `ProgressionWorldAdapter`.
public protocol ProgressionWorldPort: AnyObject {
    func nearestTrainer() -> TrainerOffer?
    func playerGold() -> Int
    func trainerOffer(for key: ReferenceKey) -> TrainerOffer?
}
