// The one-handed weapon an actor holds in its left hand. The item is also in the
// equipped set, so every reader of worn items still sees it. See
// docs/engine/inventory-state.md#the-left-hand.

public import OpenSkyFormatsESM

/// A copy of `item` in the left hand. With `paired`, a second copy is in the right hand,
/// so two iron swords can be worn from one stack.
nonisolated public struct LeftHandHold: Equatable, Sendable {
    public let item: FormID
    public let paired: Bool

    public init(item: FormID, paired: Bool = false) {
        self.item = item
        self.paired = paired
    }
}

/// The weapon each hand holds; one item for both hands of a pair.
nonisolated public struct WornWeapons: Equatable, Sendable {
    public let right: FormID?
    public let left: FormID?

    public init(right: FormID?, left: FormID?) {
        self.right = right
        self.left = left
    }

    /// The weapon in each hand. `hands` answers the hands a weapon takes, nil for an item
    /// that is no weapon. Without a left-hand hold, a second one-handed weapon in the set
    /// is the left one: a baseline outfit can list two, and it holds both.
    public static func resolve(
        in equipped: [FormID], leftHand: LeftHandHold?, hands: (FormID) -> HandSlots?
    ) -> Self {
        let held = equipped.filter { hands($0) != nil }
        if let leftHand {
            let right = leftHand.paired ? leftHand.item : held.first {
                $0 != leftHand.item && hands($0)?.contains(.rightHand) == true
            }
            return Self(right: right, left: leftHand.item)
        }
        guard let right = held.first else { return Self(right: nil, left: nil) }
        guard hands(right) == .rightHand else { return Self(right: right, left: nil) }
        return Self(right: right, left: held.dropFirst().first { hands($0) == .rightHand })
    }
}
