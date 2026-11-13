// The HUD notices of a landed spell or poison: a target refusing the player's spell, from
// `sMagicEffectResisted` and `sMagicEffectNotApplied`, whose names read swapped against
// their texts, and the player poisoned. See docs/engine/magic.md#hit-notices.

public import OpenSkyGameData
public import OpenSkyMagicInterface

nonisolated public enum MagicHitNoticeText: String, GameSettingTextKey {
    /// `%s` is the target, then the spell.
    case tooPowerful = "sMagicEffectResisted"
    case resisted = "sMagicEffectNotApplied"
    /// A poison's effect landed on the player, once per dose.
    case poisoned = "sPoisoned"

    public var fallback: String {
        switch self {
        case .tooPowerful: "%s is too powerful for %s."
        case .resisted: "%s resisted %s."
        case .poisoned: "You have been poisoned."
        }
    }

    /// The notice for one refusal of a player's spell; nil when the game shows none.
    /// A touch spell never shows the "resisted" line.
    public static func notice(
        for refusal: SpellTargetRefusal, names: (target: String, spell: String), isTouch: Bool,
        texts: GameSettingTexts<Self>
    ) -> String? {
        let text: Self
        if refusal.aboveLevelCap {
            text = .tooPowerful
        } else if refusal.nothingLanded, !isTouch {
            text = .resisted
        } else {
            return nil
        }
        return SettingTextFormat.fill(texts[text], [names.target, names.spell])
    }
}
