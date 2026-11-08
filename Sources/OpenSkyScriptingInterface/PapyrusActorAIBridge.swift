import Foundation
public import OpenSkyFormatsESM
import OpenSkyWorldInterface

/// What the actor AI natives reach. The app answers it.
public protocol PapyrusActorAIBridge: AnyObject {
    func evaluatePackage(_ actor: ReferenceKey)
    /// Nil `vehicle`, or the rider itself, takes the rider off its vehicle.
    func setVehicle(_ rider: ReferenceKey, vehicle: ReferenceKey?)
    func tether(_ vehicle: ReferenceKey, to horse: ReferenceKey)
    /// False when the actor cannot play the idle.
    func playIdle(_ idle: ResolvedFormID, on actor: ReferenceKey) -> Bool
    func setPlayerAIDriven(_ driven: Bool)
    /// `dependent` takes `owner`'s idle events too; false removes the link.
    func linkDependentAnimation(_ dependent: ReferenceKey, to owner: ReferenceKey, linked: Bool)
    /// Plays the idle with `target` as its Target; a paired idle plays the target's half.
    func playIdle(_ idle: ResolvedFormID, on actor: ReferenceKey, with target: ReferenceKey)
        -> Bool
    /// The same for the idle tree with this editor ID, such as `IdleVampireFeed`.
    func playIdle(editorID: String, on actor: ReferenceKey, with target: ReferenceKey) -> Bool
    /// True while the actor plays either half of a paired kill move.
    func isInKillMove(_ actor: ReferenceKey) -> Bool
}
