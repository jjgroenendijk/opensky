import Foundation
public import OpenSkyFormatsESM

/// The arguments of `Actor.ShowGiftMenu` (CK wiki "ShowGiftMenu - Actor").
nonisolated public struct GiftMenuRequest: Equatable, Sendable {
    /// True: the player gives. False: the actor gives.
    public var giving: Bool
    /// Items and keywords a shown item must match; nil shows every item.
    public var filter: Set<ReferenceKey>?
    public var showsStolenItems: Bool

    public init(giving: Bool, filter: Set<ReferenceKey>? = nil, showsStolenItems: Bool = false) {
        self.giving = giving
        self.filter = filter
        self.showsStolenItems = showsStolenItems
    }

    /// `identities` are the item itself and its keywords.
    public func shows(stolen: Bool, identities: Set<ReferenceKey>) -> Bool {
        guard showsStolenItems || !stolen else { return false }
        return filter.map { !$0.isDisjoint(with: identities) } ?? true
    }
}
