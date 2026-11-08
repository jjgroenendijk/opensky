import Foundation
public import OpenSkyFormatsESM

/// What the furniture natives reach. The app answers it.
public protocol PapyrusFurnitureBridge: AnyObject {
    /// Whether an actor uses `marker` of the furniture, or any marker when nil. A
    /// reserved marker counts too unless `ignoringReserved`.
    func isFurnitureInUse(_ furniture: ReferenceKey, marker: Int?, ignoringReserved: Bool) -> Bool
    /// Turns the seated player's first-person view by `degrees` from the seat's
    /// facing; negative looks left.
    func setSittingRotation(degrees: Float)
}
