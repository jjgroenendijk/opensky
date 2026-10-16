// The words the magic menu uses for a spell's type, casting, and delivery, from the
// `sMagicType*`, `sMagic<casting>`, and `sMagicDelivery*` string settings.
// See docs/engine/spellcasting.md.

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

    private func word(_ setting: String?) -> String? {
        setting.flatMap { words[$0] }
    }

    static let settings = [
        "Spell", "Disease", "Power", "LesserPower", "Ability", "Poison", "VoicePower"
    ].map { "sMagicType\($0)" } + [
        "sMagicConstantEffect", "sMagicFireAndForget", "sMagicConcentration"
    ] + ["Self", "Touch", "Aimed", "TargetActor", "TargetLocation"].map { "sMagicDelivery\($0)" }

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
