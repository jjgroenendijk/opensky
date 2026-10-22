// A perk effect whose function picks something instead of computing a number: a spell
// to cast, a text, or an activation button. UESP "Function Types" 08 to 0B and 0F.
// See docs/engine/perks.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

/// One owned, condition-passing effect at an entry point that picks a spell, a text,
/// or an activation button.
nonisolated public struct PerkEntryPointChoice: Sendable {
    /// The SPEL a select-spell or activate-choice effect names, resolved.
    public let spell: ResolvedSpell?
    /// The `EPFD` text of a select-text or set-text effect.
    public let text: PerkFunctionData?
    /// The add-activate-choice button, its flags, and the perk whose fragment it runs.
    public let activation: PerkActivateChoice?

    /// Nil when the effect's function computes a number.
    public init?(effect: ResolvedPerkEffect, perk: ResolvedPerk? = nil) {
        guard case let .entryPoint(payload) = effect.effect.data, Self.carries(payload.function)
        else { return nil }
        spell = effect.spell
        switch effect.effect.functionData {
        case .text?, .localizedText?:
            text = effect.effect.functionData
        default:
            text = nil
        }
        activation = payload.function == .addActivateChoice
            ? PerkActivateChoice(effect: effect.effect, perk: perk)
            : nil
    }

    /// A select-spell choice, as a fake world answers one.
    public init(spell: ResolvedSpell) {
        self.spell = spell
        text = nil
        activation = nil
    }

    /// A select-text choice, as a fake world answers one.
    public init(text: String) {
        spell = nil
        self.text = .text(text)
        activation = nil
    }

    /// An activate choice, as a fake world answers one.
    public init(activation: PerkActivateChoice, spell: ResolvedSpell? = nil) {
        self.spell = spell
        text = nil
        self.activation = activation
    }

    /// Whether a choice reader carries out `function`. `Add Leveled List` is not one:
    /// no vanilla entry point uses it.
    public static func carries(_ function: PerkFunction) -> Bool {
        switch function {
        case .selectSpell, .addActivateChoice, .selectText, .setText: true
        default: false
        }
    }

    /// The plain text of a select-text effect, such as a graph variable name.
    public var inlineText: String? {
        switch text {
        case let .text(value)?: value
        case let .localizedText(.inline(value))?: value
        default: nil
        }
    }
}
