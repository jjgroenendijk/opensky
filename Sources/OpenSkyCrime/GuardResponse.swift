// What a guard does about the player's bounty. A guard is a member of the `GFAC`
// faction (`IsGuardFaction`) whose `CRIF` names the crime faction; all 463 such
// NPC_ records on this install confirm it. `CRVA` flags choose arrest or attack
// (<https://ck.uesp.net/wiki/Faction>). "High enough" is `iAttackOnSightViolent`,
// 2999 (<https://ck.uesp.net/wiki/Category:Settings>). See docs/engine/guard-response.md.

import Foundation
import OpenSkyCrimeInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldInterface

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
    /// `entry` is the faction's ledger row; nil owes nothing.
    public static func response(
        _ entry: CrimeLedgerEntry?,
        values: Faction.CrimeValues?,
        settings: CrimeSettings = .vanilla
    ) -> CrimeResponse {
        guard let entry, entry.gold > 0, let values else { return .none }
        // CK wiki "Creating a Custom Crime Faction": without Arrest, guards "always try
        // to kill the player on sight if there is a bounty".
        let pastLine = values.attackOnSight
            && settings.attacksOnSight(nonViolent: entry.nonViolentGold, violent: entry.violentGold)
        guard values.arrest, !pastLine else { return .attackOnSight(bounty: entry.gold) }
        return .confront(bounty: entry.gold)
    }
}

/// The crime term of the hostility derivation, over a snapshot of the player's
/// ledger. A guard is hostile when its faction attacks on sight at this bounty or
/// the player resisted arrest. A snapshot, because the derivation is nonisolated.
nonisolated public struct GuardCrimeHostility: CrimeHostilitySource, Equatable, Sendable {
    public let guardFaction: ReferenceKey?
    /// The ledger row per owed crime faction, which is all the term reads.
    public let bounties: [ReferenceKey: CrimeLedgerEntry]
    /// Each crime faction's `CRVA`.
    public let crimeValues: [ReferenceKey: Faction.CrimeValues]
    /// Crime factions the player resisted arrest with while owing them.
    public let resisted: Set<ReferenceKey>
    public let settings: CrimeSettings
    /// Per crime faction, the actors other than the player that struck one of its
    /// people first. Its guards fight them.
    public var actorCriminals: [ReferenceKey: Set<ReferenceKey>] = [:]

    public func crimeReaction(
        of observer: ActorSocialProfile,
        toward target: ActorSocialProfile
    ) -> ActorReaction? {
        if target.key != .player {
            guard
                let faction = GuardRecognition.policedFaction(
                    of: observer, guardFaction: guardFaction
                ),
                actorCriminals[faction]?.contains(target.key) == true
            else { return nil }
            return .enemy
        }
        guard
            let faction = GuardRecognition.policedFaction(
                of: observer, guardFaction: guardFaction
            ),
            let bounty = bounties[faction], bounty.gold > 0
        else { return nil }
        if resisted.contains(faction) {
            return .enemy
        }
        if
            case .attackOnSight = CrimeResponsePolicy.response(
                bounty, values: crimeValues[faction], settings: settings
            )
        {
            return .enemy
        }
        return nil
    }

    public init(
        guardFaction: ReferenceKey?,
        bounties: [ReferenceKey: CrimeLedgerEntry],
        crimeValues: [ReferenceKey: Faction.CrimeValues],
        resisted: Set<ReferenceKey>,
        settings: CrimeSettings = .vanilla
    ) {
        self.guardFaction = guardFaction
        self.bounties = bounties
        self.crimeValues = crimeValues
        self.resisted = resisted
        self.settings = settings
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

    /// What to do this tick. At most one confrontation at a time, with the nearest
    /// eligible guard. An attack-on-sight guard is skipped: it is already hostile.
    public func actions(
        guards: [GuardCandidate],
        bounty: (ReferenceKey) -> CrimeLedgerEntry?,
        values: (ReferenceKey) -> Faction.CrimeValues?,
        settings: CrimeSettings = .vanilla,
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
                bounty(guardView.crimeFaction),
                values: values(guardView.crimeFaction),
                settings: settings
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
                bounty: bounty(nearest.crimeFaction)?.gold ?? 0
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
