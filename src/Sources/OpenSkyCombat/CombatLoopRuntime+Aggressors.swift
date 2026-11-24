// Who started a fight, and the facts the help rule reads from the running fight.
// See docs/engine/combat.md#started-the-fight.

import OpenSkyActorsInterface
public import OpenSkyCombatInterface
import OpenSkyFormatsESM

extension CombatLoopRuntime {
    /// The NPC pairs perception tracks.
    public var watchedPairs: Set<CombatFoePair> {
        foePairs.union(allyWatchPairs)
    }

    /// Marks `key`, which has just entered combat, when it started the fight. One that
    /// joins an ally takes the ally's mark. One the player struck did not start it.
    func noteEnteredCombat(_ key: ReferenceKey, provoked: Bool, world: any CombatLoopWorld) {
        guard markJudged.insert(key).inserted else { return }
        if let ally = joinedGroups.removeValue(forKey: key) {
            if aggressors.contains(ally) {
                aggressors.insert(key)
            }
            return
        }
        if isForcedOntoPlayer(key) {
            if !world.combatIsGuard(key) {
                aggressors.insert(key)
            }
            return
        }
        guard !provoked, let target = targets[key] else { return }
        let started = target == world.combatPlayer.key
            ? world.combatIsHostile(key, toward: target)
            && !world.combatAttacksPlayerOnSightForCrimes(key)
            : !aggressors.contains(target) && !world.combatIsHostile(target, toward: key)
        if started {
            aggressors.insert(key)
        }
    }

    /// Drops `key`'s mark when its fight ends.
    func forgetMark(of key: ReferenceKey) {
        aggressors.remove(key)
        markJudged.remove(key)
        joinedGroups.removeValue(forKey: key)
    }

    /// Whether `helper` joins `ally`'s fight on `ally`'s side.
    func helps(_ helper: ReferenceKey, _ ally: ReferenceKey, world: any CombatLoopWorld) -> Bool {
        CombatHelpRule.helps(helper, ally, facts: CombatHelpView(runtime: self, world: world))
    }
}

/// The help rule's facts, read from the running fight and its world.
@MainActor
struct CombatHelpView: CombatHelpFacts {
    let runtime: CombatLoopRuntime
    let world: any CombatLoopWorld

    var player: ReferenceKey {
        world.combatPlayer.key
    }

    func owner(of key: ReferenceKey) -> ReferenceKey? {
        runtime.commanders[key]
    }

    func isTeammate(_ key: ReferenceKey) -> Bool {
        world.combatIsTeammate(key)
    }

    func morality(of key: ReferenceKey) -> Float {
        world.combatMorality(of: key)
    }

    func startedFight(_ key: ReferenceKey) -> Bool {
        runtime.aggressors.contains(key)
    }

    func committedCrime(_ key: ReferenceKey, judgedBy helper: ReferenceKey) -> Bool {
        switch world.combatCrimeStanding(of: key, judgedBy: helper) {
        case .clean: false
        case .criminal: true
        case .criminalWhileAGuardFights: opponents(of: key).contains { world.combatIsGuard($0) }
        }
    }

    func opponents(of key: ReferenceKey) -> [ReferenceKey] {
        var foes = Set(runtime.behaviors.keys.filter { fighter in
            fighter != key && isFighting(fighter) && runtime.combatTarget(of: fighter) == key
        })
        if key != player, isFighting(key), let target = runtime.combatTarget(of: key) {
            foes.insert(target)
        }
        return foes.sorted()
    }

    func opposes(_ helper: ReferenceKey, _ opponent: ReferenceKey) -> Bool {
        if isFighting(helper), runtime.combatTarget(of: helper) == opponent {
            return true
        }
        return opponent == player
            ? runtime.hostility(of: helper) == .hostile
            : world.combatIsHostile(helper, toward: opponent)
    }

    func attacksPlayerOnSightForCrimes(_ key: ReferenceKey) -> Bool {
        world.combatAttacksPlayerOnSightForCrimes(key)
    }

    func assistsByTemperament(_ helper: ReferenceKey, ally: ReferenceKey) -> Bool {
        world.combatAssists(helper, ally: ally)
    }

    private func isFighting(_ key: ReferenceKey) -> Bool {
        runtime.behaviors[key]?.isEngaged == true
    }
}
