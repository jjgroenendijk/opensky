// Whether one actor helps another in a fight: the ordered checks of
// docs/engine/combat.md#who-an-assisting-actor-fights. Facts in, yes or no out.

import OpenSkyFormatsESM

/// Whether a helper counts an actor a criminal.
nonisolated public enum CombatCrimeStanding: Equatable, Sendable {
    case clean
    case criminal
    /// The player resisted the helper's crime faction a while ago. The player counts as a
    /// criminal only while a guard fights them.
    case criminalWhileAGuardFights
}

/// What the help rule reads about the actors it judges.
@MainActor
protocol CombatHelpFacts {
    var player: ReferenceKey { get }
    /// The actor that commands `key`, such as the caster of a summon.
    func owner(of key: ReferenceKey) -> ReferenceKey?
    /// Whether `key` is the player's follower.
    func isTeammate(_ key: ReferenceKey) -> Bool
    /// `key`'s Morality: 0 any crime, and 1 to 3, which the filter treats alike.
    func morality(of key: ReferenceKey) -> Float
    /// Whether `key` carries the mark of the actor that started its fight.
    func startedFight(_ key: ReferenceKey) -> Bool
    /// Whether `helper` counts `key` a criminal.
    func committedCrime(_ key: ReferenceKey, judgedBy helper: ReferenceKey) -> Bool
    /// The actors `key` fights or that fight it. Empty out of combat.
    func opponents(of key: ReferenceKey) -> [ReferenceKey]
    /// Whether `helper` fights `opponent` or attacks it on sight.
    func opposes(_ helper: ReferenceKey, _ opponent: ReferenceKey) -> Bool
    /// Whether `key` attacks the player on sight for the player's crimes.
    func attacksPlayerOnSightForCrimes(_ key: ReferenceKey) -> Bool
    /// The last step: `helper`'s Assistance against its reaction to `ally`, and no help
    /// for a frenzied ally.
    func assistsByTemperament(_ helper: ReferenceKey, ally: ReferenceKey) -> Bool
}

@MainActor
enum CombatHelpRule {
    /// Each owner or follower step asks again with other actors. A loop of owners stops
    /// here with no help.
    static let maximumDepth = 8

    static func helps(
        _ helper: ReferenceKey, _ ally: ReferenceKey?, facts: some CombatHelpFacts,
        depth: Int = 0
    ) -> Bool {
        guard let ally, depth < maximumDepth else { return false }
        guard helper != ally else { return true }
        let next = depth + 1
        if let owner = facts.owner(of: ally) {
            return helps(helper, owner, facts: facts, depth: next)
        }
        if let owner = facts.owner(of: helper) {
            return helps(owner, ally, facts: facts, depth: next)
        }
        let player = facts.player
        if facts.morality(of: helper) > 0, refusesOnMorality(helper, ally, facts: facts) {
            return facts.isTeammate(ally) && helps(helper, player, facts: facts, depth: next)
        }
        if facts.isTeammate(helper) {
            guard ally != player else { return !facts.attacksPlayerOnSightForCrimes(helper) }
            let foes = facts.opponents(of: ally)
            guard !foes.contains(player), !foes.contains(helper) else { return false }
            return helps(player, ally, facts: facts, depth: next)
        }
        if facts.isTeammate(ally) {
            return helps(helper, player, facts: facts, depth: next)
        }
        return facts.assistsByTemperament(helper, ally: ally)
    }

    /// A helper with a Morality refuses a criminal, and the actor that started the fight
    /// unless the helper already opposes one of that actor's opponents.
    static func refusesOnMorality(
        _ helper: ReferenceKey, _ ally: ReferenceKey, facts: some CombatHelpFacts
    ) -> Bool {
        if facts.committedCrime(ally, judgedBy: helper) {
            return true
        }
        guard facts.startedFight(ally) else { return false }
        return !facts.opponents(of: ally).contains { facts.opposes(helper, $0) }
    }
}
