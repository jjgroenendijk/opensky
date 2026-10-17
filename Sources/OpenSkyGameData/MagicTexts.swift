// The words the magic menu uses for a spell's type, casting, and delivery, from the
// `sMagicType*`, `sMagic<casting>`, and `sMagicDelivery*` string settings, and the
// effects list's time units. See docs/engine/spellcasting.md and docs/engine/magic.md.

import Foundation
import OpenSkyFormatsESM

nonisolated public struct MagicTexts: Equatable, Sendable {
    /// Resolved words by setting editor ID. A word not resolved reads as OpenSky's own.
    public var words: [String: String] = [:]

    public static let vanilla = Self()

    public init() {}

    public func name(of type: SpellType) -> String {
        let setting: String? = switch type {
        case .spell: "sMagicTypeSpell"
        case .disease: "sMagicTypeDisease"
        case .power: "sMagicTypePower"
        case .lesserPower: "sMagicTypeLesserPower"
        case .ability: "sMagicTypeAbility"
        case .poison: "sMagicTypePoison"
        case .voice: "sMagicTypeVoicePower"
        case .addiction, .unknown: nil
        }
        return word(setting) ?? type.description
    }

    public func name(of casting: MagicEffectCastingType) -> String {
        let setting: String? = switch casting {
        case .constantEffect: "sMagicConstantEffect"
        case .fireAndForget: "sMagicFireAndForget"
        case .concentration: "sMagicConcentration"
        case .scroll, .unknown: nil
        }
        return word(setting) ?? casting.description
    }

    public func name(of delivery: MagicEffectDelivery) -> String {
        let setting: String? = switch delivery {
        case .selfTarget: "sMagicDeliverySelf"
        case .touch: "sMagicDeliveryTouch"
        case .aimed: "sMagicDeliveryAimed"
        case .targetActor: "sMagicDeliveryTargetActor"
        case .targetLocation: "sMagicDeliveryTargetLocation"
        case .unknown: nil
        }
        return word(setting) ?? delivery.description
    }

    /// The school a magic skill names, or nil for a skill that is not a school.
    public func school(of skill: Int32) -> String? {
        guard
            let name = ActorValueIdentity.name(at: skill),
            Self.schools.contains(name)
        else { return nil }
        return word("sMagicSchool\(name)") ?? name
    }

    /// Novice below 25, Apprentice below 50, Adept below 75, Expert below 100, then Master.
    public func level(minimumSkill: UInt32) -> String {
        let index = min(Int(minimumSkill) / 25, Self.levels.count - 1)
        let (setting, fallback) = Self.levels[index]
        return word("s\(setting)DisplayName") ?? fallback
    }

    static let levels = [
        ("Novice", "Novice"), ("Apprentice", "Apprentice"), ("Journeyman", "Adept"),
        ("Expert", "Expert"), ("Master", "Master")
    ]

    static let schools = ["Alteration", "Conjuration", "Destruction", "Illusion", "Restoration"]

    /// The word a setting resolved to, else `fallback`.
    public func word(_ setting: String, or fallback: String) -> String {
        words[setting] ?? fallback
    }

    /// "12 secs", "2 mins", "1 hour": seconds below a minute, then whole minutes,
    /// then whole hours, each rounded up.
    public func timeLeft(_ seconds: Float) -> String {
        let (count, unit): (Int, String) = switch seconds {
        case ..<60: (Int(seconds.rounded(.up)), "Sec")
        case ..<3600: (Int((seconds / 60).rounded(.up)), "Min")
        default: (Int((seconds / 3600).rounded(.up)), "Hour")
        }
        let name = count == 1 ? unit : unit + "s"
        return "\(count) " + word("sEffectsListDisplay\(name)", or: name.lowercased())
    }

    private func word(_ setting: String?) -> String? {
        setting.flatMap { words[$0] }
    }

    static let settings = [
        "Spell", "Disease", "Power", "LesserPower", "Ability", "Poison", "VoicePower"
    ].map { "sMagicType\($0)" } + [
        "sMagicConstantEffect", "sMagicFireAndForget", "sMagicConcentration"
    ] + ["Self", "Touch", "Aimed", "TargetActor", "TargetLocation"].map { "sMagicDelivery\($0)" }
        + schools.map { "sMagicSchool\($0)" }
        + ["Potion", "Enchantment"].map { "sMagicType\($0)" } + ["sIngredient"]
        + ["Sec", "Secs", "Min", "Mins", "Hour", "Hours"].map { "sEffectsListDisplay\($0)" }
        + levels.map { "s\($0.0)DisplayName" }

    public static func resolve(
        store: GameSettingStore, text: (LString) -> String? = { _ in nil }
    ) -> Self {
        var settings = vanilla
        for editorID in Self.settings {
            if let word = store.text(editorID).flatMap({ text($0.text) }) {
                settings.words[editorID] = word
            }
        }
        return settings
    }
}
