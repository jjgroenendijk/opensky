// The values a hostility decision is made from and reported as, and the seam crime
// answers through. The derivation itself is in OpenSkyFactions.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData

/// Everything the derivation needs to know about one actor.
///
/// A flat value rather than a lookup closure so the whole derivation is
/// testable without a world-state store, and so a caller that already has the
/// memberships in hand does not pay for them twice.
nonisolated public struct ActorSocialProfile: Equatable, Sendable {
    public let key: ReferenceKey
    /// The actor's NPC_ base identity, which is what a RELA record names. Nil
    /// for the player, who has no base record in this engine, and for a
    /// generated actor no plugin describes.
    public let base: ResolvedFormID?
    public let memberships: ActorFactionState
    /// Relationship ranks a script has set on this actor (issue #508). Consulted
    /// ahead of the `RELA` records, because that is what setting one means, and
    /// because it is the only layer that can name the player.
    public let relationshipOverrides: ActorRelationshipState
    /// The AI attributes behind the aggression check. `ActorAIData.absent` for
    /// an actor whose record authors no AIDT, which never attacks unprovoked.
    public let aiData: ActorAIData
    /// The session's explicit answer for this actor, when something already
    /// wrote one.
    public let hostilityOverride: ActorHostility?
    /// The crime faction this actor reports crimes to — its authored `CRIF`
    /// (issue #505). Nil for the player and for an actor that authors none.
    public var crimeFaction: ReferenceKey?

    public init(
        key: ReferenceKey,
        base: ResolvedFormID? = nil,
        memberships: ActorFactionState = ActorFactionState(),
        relationshipOverrides: ActorRelationshipState = ActorRelationshipState(),
        aiData: ActorAIData = .absent,
        hostilityOverride: ActorHostility? = nil,
        crimeFaction: ReferenceKey? = nil
    ) {
        self.key = key
        self.base = base
        self.memberships = memberships
        self.relationshipOverrides = relationshipOverrides
        self.aiData = aiData
        self.hostilityOverride = hostilityOverride
        self.crimeFaction = crimeFaction
    }
}

/// Which term of the precedence list produced the answer.
nonisolated public enum HostilitySource: String, Equatable, Sendable, CaseIterable {
    case runtimeOverride
    case crime
    case relationship
    case faction
    case defaultNeutral

    public var displayName: String {
        switch self {
        case .runtimeOverride: "runtime override"
        case .crime: "crime"
        case .relationship: "relationship"
        case .faction: "faction relation"
        case .defaultNeutral: "default"
        }
    }
}

/// One derivation's whole answer: what came out, what the records said, and
/// which term said it.
///
/// The reaction travels beside the hostility because they are different facts.
/// An unaggressive actor regards a bandit as an enemy and still does not attack
/// it, and a panel that showed only the hostility would make that look like the
/// records were being ignored.
nonisolated public struct HostilityDecision: Equatable, Sendable {
    public let hostility: ActorHostility
    public let reaction: ActorReaction
    public let source: HostilitySource

    public var isHostile: Bool {
        hostility == .hostile
    }

    public init(hostility: ActorHostility, reaction: ActorReaction, source: HostilitySource) {
        self.hostility = hostility
        self.reaction = reaction
        self.source = source
    }
}

/// Where crime joins the derivation (issues #504 and #505).
///
/// A protocol with one question rather than a closure so the bounty runtime can
/// carry its own state, and so this file names the seam in a way a reader can
/// find. `NoCrimeHostility` is what the engine runs with until #504 lands.
nonisolated public protocol CrimeHostilitySource {
    /// What `observer`'s crime bookkeeping makes of `target`, or nil when crime
    /// has no opinion — which is the answer for every pair until a bounty, a
    /// witnessed theft or an assault gives it one.
    func crimeReaction(
        of observer: ActorSocialProfile,
        toward target: ActorSocialProfile
    ) -> ActorReaction?
}

/// The crime term before crime exists.
nonisolated public struct NoCrimeHostility: CrimeHostilitySource, Sendable {
    public func crimeReaction(
        of observer: ActorSocialProfile,
        toward target: ActorSocialProfile
    ) -> ActorReaction? {
        nil
    }

    public init() {}
}
