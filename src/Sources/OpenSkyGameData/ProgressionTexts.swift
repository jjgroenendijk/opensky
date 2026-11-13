// The HUD notices of skill and character progress, from the `sSkillIncreased` and
// `sLevelUpAvailable` string settings, and the perk card's requirement word.
// See docs/engine/skill-advancement.md.

nonisolated public struct ProgressionTexts: Equatable, Sendable {
    /// `%s` is the skill, `%i` its new level.
    public var skillIncreased = "%s increased to %i"
    public var levelUpAvailable = "Level up available."
    /// The perk card's requirement word, before the skill and level.
    public var requires = "Requires"
    /// Put before the next rank's description on the card of a part-owned perk.
    public var nextRank = "Next Rank:"

    public static let vanilla = Self()

    public init() {}

    public func skillIncreasedText(skill: String, level: Int) -> String {
        SettingTextFormat.fill(skillIncreased, [skill, "\(level)"])
    }

    /// "Requires One-Handed 20".
    public func requirementText(skill: String, level: Int) -> String {
        "\(requires) \(skill) \(level)"
    }

    /// The card text of a perk whose first `owned` ranks the player has: the owned
    /// rank's description, then the next rank's after `sStatsNextRank`.
    public func perkCardText(owned: String?, next: String?) -> String {
        guard let owned, let next, !owned.isEmpty, !next.isEmpty else {
            return next ?? owned ?? ""
        }
        return "\(owned)\n\(nextRank) \(next)"
    }

    public static func resolve(
        store: GameSettingStore, text: GameTextResolver = { _ in nil }
    ) -> Self {
        var texts = vanilla
        store.read("sSkillIncreased", into: &texts, \.skillIncreased, text: text)
        store.read("sLevelUpAvailable", into: &texts, \.levelUpAvailable, text: text)
        store.read("sRequirementsText", into: &texts, \.requires, text: text)
        store.read("sStatsNextRank", into: &texts, \.nextRank, text: text)
        return texts
    }
}
