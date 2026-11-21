// Which kill stats a death by the player raises, from the victim's `ActorType*`
// keywords. See docs/engine/statistics.md, Combat.

nonisolated public enum KillStats {
    /// The stat names to raise. `hasKeyword` answers for the victim's race and base.
    public static func stats(hasKeyword: (String) -> Bool) -> [String] {
        var stats: [String] = []
        if hasKeyword("ActorTypeNPC") {
            stats.append("People Killed")
        }
        let animal = hasKeyword("ActorTypeAnimal")
        let undead = hasKeyword("ActorTypeUndead")
        if animal {
            stats.append("Animals Killed")
        }
        if undead {
            stats.append("Undead Killed")
        }
        if hasKeyword("ActorTypeDaedra") {
            stats.append("Daedra Killed")
        }
        if hasKeyword("ActorTypeDwarven") {
            stats.append("Automatons Killed")
        }
        if hasKeyword("ActorTypeCreature"), !animal, !undead {
            stats.append("Creatures Killed")
        }
        return stats
    }
}
