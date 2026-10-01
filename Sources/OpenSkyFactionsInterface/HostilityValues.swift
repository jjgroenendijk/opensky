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
    /// Relationship ranks a script has set on this actor. Consulted ahead of the
    /// `RELA` records, and the only layer that can name the player.
    public let relationshipOverrides: ActorRelationshipState
    /// The AI attributes behind the aggression check. `ActorAIData.absent` for
    /// an actor whose record authors no AIDT, which never attacks unprovoked.
    public let aiData: ActorAIData
    /// The session's explicit answer for this actor, when something already
    /// wrote one.
    public let hostilityOverride: ActorHostility?
    /// The crime faction this actor reports crimes to: its authored `CRIF`.
    /// Nil for the player and for an actor that authors none.
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

/// One derivation's whole answer. The reaction travels beside the hostility
/// because an unaggressive actor can regard a bandit as an enemy and still not
/// attack it.
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

/// Where crime joins the derivation. A protocol rather than a closure, so the
/// bounty runtime can carry its own state.
nonisolated public protocol CrimeHostilitySource: Sendable {
    /// Nil when crime has no opinion, which holds until a bounty, a witnessed
    /// theft, or an assault gives it one.
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
