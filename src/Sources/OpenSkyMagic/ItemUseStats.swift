// Which stat eating, drinking, or reading raises. See docs/engine/statistics.md.

public import OpenSkyMagicInterface

nonisolated public enum ItemUseStats {
    /// Nil for a poison drunk, which no stat counts.
    public static func stat(
        of kind: ActiveEffectSourceKind, isFood: Bool, isPoison: Bool
    ) -> String? {
        switch kind {
        case .ingredient: "Ingredients Eaten"
        case .potion where isFood: "Food Eaten"
        case .potion where !isPoison: "Potions Used"
        default: nil
        }
    }

    /// The stats one first reading raises. A skill book is not counted as a book read.
    public static func bookStats(isSkillBook: Bool, taughtSpell: Bool) -> [String] {
        var stats = [isSkillBook ? "Skill Books Read" : "Books Read"]
        if taughtSpell {
            stats.append("Spells Learned")
        }
        return stats
    }
}
