// What a guard does about the player's bounty (issue #505, roadmap item 21.6):
// who counts as a guard, which bounty earns a conversation and which earns a
// sword, and the crime term the hostility derivation reads.
//
// ## Who is a guard
//
// An actor polices a crime faction when it is a member of the faction the
// `GFAC` ("Guard Faction") default object names and its `CRIF` names that
// crime faction. Both halves were confirmed on this install rather than
// assumed: `GFAC` names `IsGuardFaction`, and every one of the 463 NPC_ records
// in `IsGuardFaction` authors a `CRIF` it is also a member of —
// `GuardWhiterunImperialPatrolDay` reports to `CrimeFactionWhiterun`. The
// Creation Kit wiki gives the `CRIF` meaning: `Actor.GetCrimeFaction` "Obtains
// the Faction this actor reports it's crimes to"
// (<https://ck.uesp.net/wiki/GetCrimeFaction_-_Actor>).
//
// ## Arrest or attack
//
// The crime faction's `CRVA` carries two flags the Creation Kit's Faction page
// defines: "Attack on Sight: If checked, guards will attack the player on sight
// if crime gold is high enough" and "Arrest: If checked, guards will try to
// arrest the player" (<https://ck.uesp.net/wiki/Faction>). How high "high
// enough" is has no open source. No `iCrimeGold*` setting prices it on this
// install — `openskycli gmst list --prefix iCrime` reports only
// `iCrimeGoldStealHorse` and `iCrimeGoldWerewolf` — and UESP's talk pages only
// say that "Normally a 1000 bounty will cause them to arrest you on sight".
// `CrimeResponsePolicy.attackOnSightGold` is therefore 1000, the vanilla murder
// bounty, stated as this engine's choice and flagged in docs/engine/guard-response.md.
//
// Documented in docs/engine/guard-response.md.

import Foundation
import OpenSkyFormats

/// What a guard does on seeing the player with a bounty.
nonisolated public enum CrimeResponse: Equatable, Sendable {
    /// Nothing: no bounty, or a faction that neither arrests nor attacks.
    case none
    /// Walk up and start the arrest conversation.
    case confront(bounty: Int32)
    /// Skip the conversation and fight.
    case attackOnSight(bounty: Int32)
}

/// The `CRVA` flags turned into a response for one bounty.
nonisolated public enum CrimeResponsePolicy: Sendable {
    /// The bounty at or above which an attack-on-sight faction stops talking.
    /// This engine's number, not a documented one; see the file header.
    public static let attackOnSightGold: Int32 = 1000

    public static func response(bounty: Int32, values: Faction.CrimeValues?) -> CrimeResponse {
        guard bounty > 0, let values else { return .none }
        if values.attackOnSight, bounty >= attackOnSightGold {
            return .attackOnSight(bounty: bounty)
        }
        return values.arrest ? .confront(bounty: bounty) : .none
    }
}

/// Who polices what.
nonisolated public enum GuardRecognition: Sendable {
    /// The crime faction `profile` polices, or nil when it is not a guard.
    ///
    /// Membership in the guard faction is what makes a guard; `CRIF` is which
    /// hold it answers for. A guard with no `CRIF` polices nothing, and a load
    /// order with no `GFAC` has no guards at all.
    public static func policedFaction(
        of profile: ActorSocialProfile,
        guardFaction: ReferenceKey?
    ) -> ReferenceKey? {
        guard
            let guardFaction,
            let crimeFaction = profile.crimeFaction,
            profile.memberships.isMember(of: guardFaction)
        else { return nil }
        return crimeFaction
    }
}

/// The crime term of the hostility derivation, over a snapshot of the player's
/// ledger (issue #505).
///
/// A guard that polices a faction the player owes is hostile when that faction
/// attacks on sight at this bounty, or when the player resisted arrest with it.
/// Everybody else gets no opinion from crime, so the record terms decide. A
/// value snapshot rather than a live handle because the derivation is
/// nonisolated; the session refreshes it whenever the ledger or the resisted
/// set moves.
nonisolated public struct GuardCrimeHostility: CrimeHostilitySource, Sendable {
    public let guardFaction: ReferenceKey?
    /// Bounty per crime faction, which is all the term reads.
    public let bounties: [ReferenceKey: Int32]
    /// Each crime faction's `CRVA`.
    public let crimeValues: [ReferenceKey: Faction.CrimeValues]
    /// Crime factions the player resisted arrest with while owing them.
    public let resisted: Set<ReferenceKey>

    public func crimeReaction(
        of observer: ActorSocialProfile,
        toward target: ActorSocialProfile
    ) -> ActorReaction? {
        guard
            target.key == .player,
            let faction = GuardRecognition.policedFaction(
                of: observer, guardFaction: guardFaction
            ),
            let bounty = bounties[faction], bounty > 0
        else { return nil }
        if resisted.contains(faction) {
            return .enemy
        }
        if
            case .attackOnSight = CrimeResponsePolicy.response(
                bounty: bounty, values: crimeValues[faction]
            )
        {
            return .enemy
        }
        return nil
    }

    public init(
        guardFaction: ReferenceKey?,
        bounties: [ReferenceKey: Int32],
        crimeValues: [ReferenceKey: Faction.CrimeValues],
        resisted: Set<ReferenceKey>
    ) {
        self.guardFaction = guardFaction
        self.bounties = bounties
        self.crimeValues = crimeValues
        self.resisted = resisted
    }
}

/// One guard the session can see, reduced to what the confrontation decision
/// reads.
nonisolated public struct GuardCandidate: Equatable, Sendable {
    public let guardKey: ReferenceKey
    public let crimeFaction: ReferenceKey
    /// Whether the perception pass has the player at `detected` for this guard.
    public let detectsPlayer: Bool
    /// World-space distance to the player.
    public let distance: Float

    public init(
        guardKey: ReferenceKey,
        crimeFaction: ReferenceKey,
        detectsPlayer: Bool,
        distance: Float
    ) {
        self.guardKey = guardKey
        self.crimeFaction = crimeFaction
        self.detectsPlayer = detectsPlayer
        self.distance = distance
    }
}

/// What one tick of guard response asks the session to do.
nonisolated public enum GuardAction: Equatable, Sendable {
    /// Walk toward the player: the guard has seen a bounty worth an arrest and
    /// is not yet close enough to speak.
    case pursue(guardKey: ReferenceKey, crimeFaction: ReferenceKey)
    /// Open the arrest conversation now.
    case confront(guardKey: ReferenceKey, crimeFaction: ReferenceKey, bounty: Int32)
}

/// Session state for guard response: who is mid-confrontation, who was just
/// dealt with, and which factions the player resisted.
///
/// Session state rather than a component, for the reason `assaultedActors`
/// is: it answers "what happened in this encounter", and a reloaded save starts
/// every encounter from the ledger. Recorded in docs/engine/guard-response.md.
nonisolated public struct GuardResponseState: Equatable, Sendable {
    /// How close a guard has to be to open the conversation, in world units.
    /// The interaction ray's reach, so a guard speaks from where the player
    /// could have spoken to it.
    public static let confrontDistance: Float = InteractionRay.defaultMaximumDistance
    /// Game seconds a guard waits before confronting again after a
    /// confrontation that could not run — no dialogue index, another menu in
    /// the way. One game hour, this engine's number. A conversation the player
    /// walks out of is not this case: UESP records that "If you cancel the
    /// dialogue when guards attempt to arrest you, they will attack you"
    /// (<https://en.uesp.net/wiki/Skyrim:Crime>), which is `resist`.
    public static let reconfrontGameSeconds: Double = 3600

    /// The guard currently in the arrest conversation, and its faction.
    public private(set) var active: GuardAction?
    /// Game time before which each guard will not confront again.
    public private(set) var cooldownUntil: [ReferenceKey: Double] = [:]
    /// Crime factions whose guards the player resisted.
    public private(set) var resisted: Set<ReferenceKey> = []

    public init() {}

    /// What to do this tick, given every guard in view and the player's
    /// bounties.
    ///
    /// At most one confrontation at a time — the nearest eligible guard — and
    /// none while one is already open. A guard of an attack-on-sight bounty is
    /// not listed: the hostility term already turned it hostile, and the
    /// combat loop owns what happens next.
    public func actions(
        guards: [GuardCandidate],
        bounty: (ReferenceKey) -> Int32,
        values: (ReferenceKey) -> Faction.CrimeValues?,
        now: Double
    ) -> [GuardAction] {
        guard active == nil else { return [] }
        let eligible = guards.filter { guardView in
            guard
                guardView.detectsPlayer,
                !resisted.contains(guardView.crimeFaction),
                (cooldownUntil[guardView.guardKey] ?? -.infinity) <= now
            else { return false }
            let response = CrimeResponsePolicy.response(
                bounty: bounty(guardView.crimeFaction),
                values: values(guardView.crimeFaction)
            )
            return if case .confront = response {
                true
            } else {
                false
            }
        }
        .sorted {
            $0.distance < $1.distance
                || ($0.distance == $1.distance && $0.guardKey < $1.guardKey)
        }
        guard let nearest = eligible.first else { return [] }
        if nearest.distance <= Self.confrontDistance {
            return [.confront(
                guardKey: nearest.guardKey,
                crimeFaction: nearest.crimeFaction,
                bounty: bounty(nearest.crimeFaction)
            )]
        }
        return [.pursue(guardKey: nearest.guardKey, crimeFaction: nearest.crimeFaction)]
    }

    /// Records that a confrontation opened.
    public mutating func begin(_ action: GuardAction) {
        guard case .confront = action else { return }
        active = action
    }

    /// Ends the open confrontation. A settled one (paid or jailed) needs no
    /// cooldown, because the bounty it was about is gone; one that could not
    /// run holds that guard off for `reconfrontGameSeconds`.
    public mutating func end(settled: Bool, now: Double) {
        if case let .confront(guardKey, _, _) = active, !settled {
            cooldownUntil[guardKey] = now + Self.reconfrontGameSeconds
        }
        active = nil
    }

    /// The player refused arrest: every guard of that faction turns hostile.
    public mutating func resist(_ crimeFaction: ReferenceKey, now: Double) {
        resisted.insert(crimeFaction)
        end(settled: true, now: now)
    }

    /// Forgets a faction's resistance once its bounty is gone, so paying later
    /// does not leave the guards angry forever.
    public mutating func forgive(_ crimeFaction: ReferenceKey) {
        resisted.remove(crimeFaction)
    }

    /// Drops every cooldown and resistance, for a new game or a dev reset.
    public mutating func reset() {
        self = GuardResponseState()
    }
}
