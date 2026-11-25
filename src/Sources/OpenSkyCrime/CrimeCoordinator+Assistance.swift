// What a helper deciding whether to join a fight asks the crime state: did the actor it
// would help commit a crime, and would the helper attack the player on sight for crimes.
// See docs/engine/combat.md#committed-a-crime.

public import OpenSkyCrimeInterface
import OpenSkyFactionsInterface
public import OpenSkyFormatsESM
import OpenSkyGameData

extension CrimeCoordinator {
    /// Game seconds after resisting arrest in which the player counts as a criminal to
    /// every member of that crime faction, with no guard needed.
    static let resistedCrimeSeconds: Double = 300
    /// Gold of the crimes a non-guard knows the player committed, from which it attacks
    /// the player on sight.
    static let knownCrimeAttackGold: Int32 = 100

    /// Whether `helper` counts `actor` a criminal.
    public func assistStanding(
        of actor: ReferenceKey, judgedBy helper: ReferenceKey
    ) -> CrimeAssistStanding {
        AssistRules(owner: self).assistStanding(of: actor, judgedBy: helper)
    }

    /// Whether `key` polices a crime faction as a guard.
    public func isGuard(_ key: ReferenceKey) -> Bool {
        policedFaction(of: key) != nil
    }

    /// A guard attacks the player on sight past its faction's bounty line. Anyone else
    /// does while its crime faction counts the player as an enemy, or once the crimes it
    /// saw add up to `knownCrimeAttackGold`.
    public func attacksPlayerOnSightForCrimes(_ key: ReferenceKey) -> Bool {
        AssistRules(owner: self).attacksPlayerOnSightForCrimes(key)
    }
}

extension CrimeCoordinator {
    /// Decides whether a crime makes an actor help or attack on sight.
    struct AssistRules {
        let owner: CrimeCoordinator

        func assistStanding(
            of actor: ReferenceKey, judgedBy helper: ReferenceKey
        ) -> CrimeAssistStanding {
            let world = owner.world
            if !(owner.alarm.answering[actor] ?? []).isEmpty {
                return .criminal
            }
            guard
                actor == .player,
                let faction = world.socialProfile(of: helper)?.crimeFaction,
                owner.guards.resisted.contains(faction)
            else { return .clean }
            let since = (world.gameSeconds ?? 0) - (owner.guards.resistedAt[faction] ?? -.infinity)
            return since <= CrimeCoordinator
                .resistedCrimeSeconds ? .criminal : .criminalWhileAGuardFights
        }

        func attacksPlayerOnSightForCrimes(_ key: ReferenceKey) -> Bool {
            let world = owner.world
            guard let runtime = owner.reporter?.runtime else { return false }
            if let faction = owner.policedFaction(of: key) {
                let entry = runtime.ledger().entry(for: faction)
                return runtime.settings.attacksOnSight(
                    nonViolent: entry?.nonViolentGold ?? 0, violent: entry?.violentGold ?? 0
                )
            }
            if
                let faction = world.socialProfile(of: key)?.crimeFaction,
                owner.guards.resisted.contains(faction)
            {
                return true
            }
            let known = (owner.alarm.witnesses[key]?.crimes ?? [])
                .compactMap { owner.alarm.crimes[$0] }
                .filter { $0.criminal == .player }
                .reduce(Int32(0)) { $0 + $1.gold }
            return known >= CrimeCoordinator.knownCrimeAttackGold
        }
    }
}
