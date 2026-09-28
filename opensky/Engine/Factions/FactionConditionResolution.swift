// The one place a condition asks "what does this actor belong to, and what is it
// to that one?" (issue #508, roadmap item 21.4), mirroring
// `CrimeConditionResolution` and `PerkConditionResolution`.
//
// Shaped as a resolved snapshot rather than as a live handle for the reason every
// other seam on `ConditionContext` is: the evaluator is a nonisolated value a
// build thread may run, so a condition body cannot reach into `WorldStateStore`,
// `FactionRuntime` or `RelationshipRuntime`. The caller that *is* on the main
// actor assembles the profiles and hands the result over.
//
// The FACT store rides along beside the profiles because `GetInFaction`,
// `GetFactionRank` and `GetFactionRankDifference` all take a `ptFaction`
// parameter that has to be resolved against the load order before it can be
// looked up — exactly as the crime seam resolves its `ptFactionNull`.
//
// The derivation rides along because two of the six functions are not lookups at
// all: `GetFactionRelation` is the interfaction reaction between two actors'
// whole membership sets, and `IsHostileToActor` is the entire precedence list in
// `HostilityDerivation`. Copying either into this file would be a second answer
// to keep in step with the one the combat loop uses.
//
// Documented in docs/engine/hostility.md and docs/engine/condition-functions.md.

import Foundation

/// Every actor's social profile plus the store a faction parameter resolves
/// against and the derivation that answers about a pair.
///
/// `@unchecked Sendable` for the reason `CrimeConditionResolution` is: the store
/// is an immutable value snapshot built once at load, and only its `RecordIndex`
/// back-reference keeps it from being checked automatically. `HostilityDerivation`
/// carries a `CrimeHostilitySource` existential for the same reason.
nonisolated struct FactionConditionResolution: @unchecked Sendable {
    /// Load-order FACT lookup, for the `ptFaction` parameters. Nil in a session
    /// with no faction data, which is what makes the faction functions report a
    /// gap rather than answering "belongs to nothing" for every actor.
    let factions: FactionStore?
    /// The plugin a condition's FormID parameters are spelled against.
    let sourcePlugin: String?
    /// Factions, relationships and crime over the aggression table — the same
    /// value the combat loop derives hostility from. Nil beside a nil store.
    let derivation: HostilityDerivation?

    private let profiles: [ReferenceKey: ActorSocialProfile]

    static let empty = FactionConditionResolution()

    init(
        factions: FactionStore? = nil,
        sourcePlugin: String? = nil,
        derivation: HostilityDerivation? = nil,
        profiles: [ReferenceKey: ActorSocialProfile] = [:]
    ) {
        self.factions = factions
        self.sourcePlugin = sourcePlugin
        self.derivation = derivation
        self.profiles = profiles
    }

    /// Whether the seam can answer at all: a session with no FACT store and no
    /// derivation cannot, and says so rather than answering zero everywhere.
    var isAvailable: Bool {
        factions != nil && derivation != nil
    }

    /// One `ptFaction` parameter as the runtime identity a membership is keyed
    /// by, or nil when this load order carries no such FACT.
    ///
    /// The record has to exist, not merely resolve — the rule the crime, perk and
    /// keyword seams apply for the same reason: plugin-relative resolution
    /// answers for any FormID whose plugin is loaded, so a parameter naming a
    /// faction no plugin defines would otherwise come back as an ordinary key and
    /// read as "not a member", which is a different answer from "this engine has
    /// no such faction".
    func key(of formID: FormID) -> ReferenceKey? {
        guard
            let sourcePlugin,
            let factions,
            let resolved = factions.resolvedID(formID, fromPlugin: sourcePlugin),
            factions.faction(resolved) != nil
        else { return nil }
        return ReferenceKey(resolved: resolved)
    }

    /// Everything the derivation knows about one actor, or nil when this session
    /// carries no profile for it — an actor no cell has streamed, or a key that
    /// names no actor at all.
    func profile(of key: ReferenceKey) -> ActorSocialProfile? {
        guard isAvailable else { return nil }
        return profiles[key]
    }

    /// Whether `actor` is in `faction` right now.
    func isMember(_ actor: ReferenceKey, of faction: ReferenceKey) -> Bool? {
        profile(of: actor)?.memberships.isMember(of: faction)
    }

    /// The rank `actor` holds in `faction`, or nil when it is not a member —
    /// which the two callers spell differently, because the condition function
    /// and the Papyrus native disagree about the number and both are documented.
    func rank(of actor: ReferenceKey, in faction: ReferenceKey) -> Int8? {
        profile(of: actor)?.memberships.rank(in: faction)
    }

    /// The faction-based reaction between two actors, or nil when either has no
    /// profile.
    ///
    /// Nil from the derivation itself — no membership pair names the other — is
    /// reported as `.neutral` here rather than passed on, because the Creation
    /// Kit calls Neutral the relation two factions hold "even if you don't
    /// specify it" and `GetFactionRelation` has no fifth value to say "unrelated"
    /// with.
    func factionReaction(
        of observer: ReferenceKey,
        toward target: ReferenceKey
    ) -> ActorReaction? {
        guard
            let derivation,
            let mine = profile(of: observer),
            let theirs = profile(of: target)
        else { return nil }
        return derivation.factionReaction(of: mine, toward: theirs) ?? .neutral
    }

    /// The signed Creation Kit relationship rank between two actors, or nil when
    /// either has no profile and when neither a script nor a `RELA` record names
    /// the pair.
    func relationshipRank(of observer: ReferenceKey, toward target: ReferenceKey) -> Int8? {
        guard
            let derivation,
            let mine = profile(of: observer),
            let theirs = profile(of: target)
        else { return nil }
        if let scripted = derivation.scriptedRank(of: mine, toward: theirs) {
            return scripted
        }
        guard
            let base = mine.base,
            let otherBase = theirs.base,
            let signed = derivation.relationships.rank(between: base, and: otherBase)?
                .signedRank
        else { return nil }
        return Int8(clamping: signed)
    }

    /// Whether `observer` is hostile to `target` right now, through the whole
    /// precedence list the combat loop uses.
    func isHostile(_ observer: ReferenceKey, toward target: ReferenceKey) -> Bool? {
        guard
            let derivation,
            let mine = profile(of: observer),
            let theirs = profile(of: target)
        else { return nil }
        return derivation.decide(mine, toward: theirs).isHostile
    }
}
