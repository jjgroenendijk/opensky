// The HUD notices of skill and character progress, from the `sSkillIncreased` and
// `sLevelUpAvailable` string settings. See docs/engine/skill-advancement.md.

import OpenSkyFormatsESM

nonisolated public struct ProgressionTexts: Equatable, Sendable {
    /// `%s` is the skill, `%i` its new level.
    public var skillIncreased = "%s increased to %i"
    public var levelUpAvailable = "Level up available."

    public static let vanilla = Self()

    public init() {}

    public func skillIncreasedText(skill: String, level: Int) -> String {
        SettingTextFormat.fill(skillIncreased, [skill, "\(level)"])
    }

    public static func resolve(
        store: GameSettingStore, text: (LString) -> String? = { _ in nil }
    ) -> Self {
        var texts = vanilla
        store.read("sSkillIncreased", into: &texts, \.skillIncreased, text: text)
        store.read("sLevelUpAvailable", into: &texts, \.levelUpAvailable, text: text)
        return texts
    }
}
