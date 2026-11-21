// Which kill stats a death by the player raises, from the victim's `ActorType*`
// keywords, its factions, and the player's beast form. See docs/engine/statistics.md,
// Combat and Kills.

nonisolated public enum KillStats {
    /// The stat names to raise. `hasKeyword` answers for the victim's race and base.
    /// `isBunny` is membership in the `AWWW` faction; `inBeastForm` is the player's
    /// `Game.SetBeastForm` flag.
    public static func stats(
        hasKeyword: (String) -> Bool, isBunny: Bool = false, inBeastForm: Bool = false
    ) -> [String] {
        var stats: [String] = inBeastForm ? ["Mauls"] : []
        if isBunny {
            stats.append("Bunnies Slaughtered")
        }
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
