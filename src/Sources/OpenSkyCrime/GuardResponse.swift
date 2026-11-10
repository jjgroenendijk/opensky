// What a guard does about the player's bounty. A guard is a member of the `GFAC`
// faction (`IsGuardFaction`) whose `CRIF` names the crime faction; all 463 such
// NPC_ records on this install confirm it. `CRVA` flags choose arrest or attack
// (<https://ck.uesp.net/wiki/Faction>). "High enough" is `iAttackOnSightViolent`,
// 2999 (<https://ck.uesp.net/wiki/Category:Settings>). See docs/engine/guard-response.md.

import Foundation
import OpenSkyCrimeInterface
import OpenSkyFactionsInterface
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldInterface

/// One guard the session can see, reduced to what the confrontation decision
/// reads.
nonisolated struct GuardCandidate: Equatable, Sendable {
    let guardKey: ReferenceKey
    let crimeFaction: ReferenceKey
    /// Whether the perception pass has the player at `detected` for this guard.
    let detectsPlayer: Bool
    /// World-space distance to the player.
    let distance: Float
}

/// What one tick of guard response asks the session to do.
nonisolated enum GuardAction: Equatable, Sendable {
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
nonisolated struct GuardResponseState: Equatable, Sendable {
    /// How close a guard has to be to open the conversation, in world units.
    /// The interaction ray's reach, so a guard speaks from where the player
    /// could have spoken to it.
    static let confrontDistance: Float = InteractionRay.defaultMaximumDistance
    /// Game seconds a guard waits before confronting again after a
    /// confrontation that could not run — no dialogue index, another menu in
    /// the way. One game hour, this engine's number. A conversation the player
    /// walks out of is not this case: UESP records that "If you cancel the
    /// dialogue when guards attempt to arrest you, they will attack you"
    /// (<https://en.uesp.net/wiki/Skyrim:Crime>), which is `resist`.
    static let reconfrontGameSeconds: Double = 3600

    /// The guard currently in the arrest conversation, and its faction.
    private(set) var active: GuardAction?
    /// Game time before which each guard will not confront again.
    private(set) var cooldownUntil: [ReferenceKey: Double] = [:]
    /// Crime factions whose guards the player resisted.
    private(set) var resisted: Set<ReferenceKey> = []

    init() {}

    /// What to do this tick. At most one confrontation at a time, with the nearest
    /// eligible guard. An attack-on-sight guard is skipped: it is already hostile.
    func actions(
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
    mutating func begin(_ action: GuardAction) {
        guard case .confront = action else { return }
        active = action
    }

    /// Ends the open confrontation. A settled one (paid or jailed) needs no
    /// cooldown, because the bounty it was about is gone; one that could not
    /// run holds that guard off for `reconfrontGameSeconds`.
    mutating func end(settled: Bool, now: Double) {
        if case let .confront(guardKey, _, _) = active, !settled {
            cooldownUntil[guardKey] = now + Self.reconfrontGameSeconds
        }
        active = nil
    }

    /// The player refused arrest: every guard of that faction turns hostile.
    mutating func resist(_ crimeFaction: ReferenceKey, now: Double) {
        resisted.insert(crimeFaction)
        end(settled: true, now: now)
    }

    /// Forgets a faction's resistance once its bounty is gone, so paying later
    /// does not leave the guards angry forever.
    mutating func forgive(_ crimeFaction: ReferenceKey) {
        resisted.remove(crimeFaction)
    }

    /// Drops every cooldown and resistance, for a new game or a dev reset.
    mutating func reset() {
        self = GuardResponseState()
    }
}
