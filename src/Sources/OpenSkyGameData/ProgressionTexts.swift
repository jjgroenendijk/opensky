// The HUD notices of skill and character progress, from the `sSkillIncreased` and
// `sLevelUpAvailable` string settings, and the perk card's requirement word.
// See docs/engine/skill-advancement.md.

nonisolated public struct ProgressionTexts: Equatable, Sendable {
    /// `%s` is the skill, `%i` its new level.
    public var skillIncreased = "%s increased to %i"
    public var levelUpAvailable = "Level up available."
    /// The perk card's requirement word, before the skill and level.
    public var requires = "Requires"

    public static let vanilla = Self()

    public init() {}

    public func skillIncreasedText(skill: String, level: Int) -> String {
        SettingTextFormat.fill(skillIncreased, [skill, "\(level)"])
    }

    /// "Requires One-Handed 20".
    public func requirementText(skill: String, level: Int) -> String {
        "\(requires) \(skill) \(level)"
    }

    public static func resolve(
        store: GameSettingStore, text: GameTextResolver = { _ in nil }
    ) -> Self {
        var texts = vanilla
        store.read("sSkillIncreased", into: &texts, \.skillIncreased, text: text)
        store.read("sLevelUpAvailable", into: &texts, \.levelUpAvailable, text: text)
        store.read("sRequirementsText", into: &texts, \.requires, text: text)
        return texts
    }
}
