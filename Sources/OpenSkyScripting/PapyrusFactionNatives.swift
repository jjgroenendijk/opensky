// The faction family of the Papyrus world bridge: membership, relationships,
// reactions, and social profiles. The default answers nothing, which is a load
// without faction data, and the natives then refuse.

import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyGameData

public struct PapyrusFactionNatives {
    /// The faction runtime, seeded for the given actor first.
    public var runtime: (ReferenceKey) -> (any FactionAccess)?
    /// No actor argument: an override exists only once a script writes one.
    public var relationships: () -> (any RelationshipAccess)?
    public var socialDecision: (ReferenceKey, ReferenceKey) -> PapyrusSocialDecision?
    /// The `NPC_` identity a `RELA` record names. Nil for the player.
    public var socialBase: (ReferenceKey) -> ResolvedFormID?
    /// The flattened `XNAM` table, which `Faction.GetReaction` reads.
    public var relationIndex: () -> FactionRelationIndex?
    /// Receives every scripted faction reaction after one changes.
    public var reactionsChanged: ([FactionReactionOverride]) -> Void
    /// For `GetCrimeFaction` and `IsGuard`.
    public var socialProfile: (ReferenceKey) -> ActorSocialProfile?

    public init(
        runtime: @escaping (ReferenceKey) -> (any FactionAccess)? = { _ in nil },
        relationships: @escaping () -> (any RelationshipAccess)? = { nil },
        socialDecision: @escaping (ReferenceKey, ReferenceKey) -> PapyrusSocialDecision? =
            { _, _ in nil },
        socialBase: @escaping (ReferenceKey) -> ResolvedFormID? = { _ in nil },
        relationIndex: @escaping () -> FactionRelationIndex? = { nil },
        reactionsChanged: @escaping ([FactionReactionOverride]) -> Void = { _ in },
        socialProfile: @escaping (ReferenceKey) -> ActorSocialProfile? = { _ in nil }
    ) {
        self.runtime = runtime
        self.relationships = relationships
        self.socialDecision = socialDecision
        self.socialBase = socialBase
        self.relationIndex = relationIndex
        self.reactionsChanged = reactionsChanged
        self.socialProfile = socialProfile
    }
}
