// The FURN record flags that decide who uses a piece of furniture and what happens
// while they do. Meanings: docs/engine/furniture.md.

import OpenSkyFormatsESM

nonisolated public struct FurnitureRules: Equatable, Sendable {
    /// Record header flag 0x20000000.
    public var childCanUse = false
    /// Record header flag 0x10000000: a seated NPC stands up when the player greets it.
    public var mustExitToTalk = false
    /// `MNAM` 0x04000000: a dragon's perch.
    public var isPerch = false
    /// `FNAM` 0x02: a Sandbox package does not pick it.
    public var ignoredBySandbox = false
    /// `NAM1`: a spell on the actor while it uses the furniture.
    public var associatedSpell: FormID?

    public init(
        childCanUse: Bool = false, mustExitToTalk: Bool = false, isPerch: Bool = false,
        ignoredBySandbox: Bool = false, associatedSpell: FormID? = nil
    ) {
        self.childCanUse = childCanUse
        self.mustExitToTalk = mustExitToTalk
        self.isPerch = isPerch
        self.ignoredBySandbox = ignoredBySandbox
        self.associatedSpell = associatedSpell
    }

    /// A child uses only furniture marked for children; only a dragon uses a perch.
    public func admits(_ traits: FurnitureActorTraits) -> Bool {
        (!traits.isChild || childCanUse) && isPerch == traits.isDragon
    }
}

/// What about an actor decides which furniture it may use.
nonisolated public struct FurnitureActorTraits: Equatable, Sendable {
    public var isChild: Bool
    public var isDragon: Bool

    public init(isChild: Bool = false, isDragon: Bool = false) {
        self.isChild = isChild
        self.isDragon = isDragon
    }
}
