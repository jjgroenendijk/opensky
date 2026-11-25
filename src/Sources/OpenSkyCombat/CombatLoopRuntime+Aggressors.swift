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
        HelpRules(owner: self).helps(helper, ally, world: world)
    }

    /// The help rule's facts for the fight as it is now.
    func helpView(world: any CombatLoopWorld) -> CombatHelpView {
        CombatHelpView(
            world: world,
            aggressors: aggressors,
            fighters: Array(behaviors.keys),
            commander: { [commanders] in commanders[$0] },
            isEngaged: { [behaviors] in behaviors[$0]?.isEngaged == true },
            combatTarget: { self.combatTarget(of: $0) },
            hostileToPlayer: { self.hostility(of: $0) == .hostile }
        )
    }
}

/// The help rule's facts, read from the running fight and its world. It takes the fight's
/// facts as values and closures, so it does not depend back on the runtime.
@MainActor
struct CombatHelpView: CombatHelpFacts {
    let world: any CombatLoopWorld
    let aggressors: Set<ReferenceKey>
    let fighters: [ReferenceKey]
    let commander: (ReferenceKey) -> ReferenceKey?
    let isEngaged: (ReferenceKey) -> Bool
    let combatTarget: (ReferenceKey) -> ReferenceKey?
    let hostileToPlayer: (ReferenceKey) -> Bool

    var player: ReferenceKey {
        world.combatPlayer.key
    }

    func owner(of key: ReferenceKey) -> ReferenceKey? {
        commander(key)
    }

    func isTeammate(_ key: ReferenceKey) -> Bool {
        world.combatIsTeammate(key)
    }

    func morality(of key: ReferenceKey) -> Float {
        world.combatMorality(of: key)
    }

    func startedFight(_ key: ReferenceKey) -> Bool {
        aggressors.contains(key)
    }

    func committedCrime(_ key: ReferenceKey, judgedBy helper: ReferenceKey) -> Bool {
        switch world.combatCrimeStanding(of: key, judgedBy: helper) {
        case .clean: false
        case .criminal: true
        case .criminalWhileAGuardFights: opponents(of: key).contains { world.combatIsGuard($0) }
        }
    }

    func opponents(of key: ReferenceKey) -> [ReferenceKey] {
        var foes = Set(fighters.filter { fighter in
            fighter != key && isFighting(fighter) && combatTarget(fighter) == key
        })
        if key != player, isFighting(key), let target = combatTarget(key) {
            foes.insert(target)
        }
        return foes.sorted()
    }

    func opposes(_ helper: ReferenceKey, _ opponent: ReferenceKey) -> Bool {
        if isFighting(helper), combatTarget(helper) == opponent {
            return true
        }
        return opponent == player
            ? hostileToPlayer(helper)
            : world.combatIsHostile(helper, toward: opponent)
    }

    func attacksPlayerOnSightForCrimes(_ key: ReferenceKey) -> Bool {
        world.combatAttacksPlayerOnSightForCrimes(key)
    }

    func assistsByTemperament(_ helper: ReferenceKey, ally: ReferenceKey) -> Bool {
        world.combatAssists(helper, ally: ally)
    }

    private func isFighting(_ key: ReferenceKey) -> Bool {
        isEngaged(key)
    }
}

extension CombatLoopRuntime {
    /// Decides whether one actor helps another in a fight.
    struct HelpRules {
        let owner: CombatLoopRuntime

        func helps(
            _ helper: ReferenceKey,
            _ ally: ReferenceKey,
            world: any CombatLoopWorld
        ) -> Bool {
            CombatHelpRule.helps(helper, ally, facts: owner.helpView(world: world))
        }
    }
}
