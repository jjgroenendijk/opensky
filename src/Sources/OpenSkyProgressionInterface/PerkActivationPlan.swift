// What one use-key press does with the Activate choices its target passes. Run-now
// choices run first; the rest are offered beside the target's own action, unless a
// choice replaces it. CK wiki "Perk Entry Point". See docs/engine/perks.md.

import Foundation

nonisolated public struct PerkActivationPlan: Sendable {
    /// What the press does after the run-now choices ran.
    public enum Step: Sendable {
        /// The target's own action, as without perks.
        case defaultAction
        /// Nothing more: every choice ran at once and one replaced the action.
        case nothing
        /// The one offered choice, with no menu. The prompt shows its label.
        case single(PerkEntryPointChoice)
        /// A menu of the offered choices, then the target's own action if kept.
        case menu
    }

    /// Choices flagged "run immediately", in priority order.
    public let immediate: [PerkEntryPointChoice]
    /// Choices the player picks from, in priority order.
    public let offered: [PerkEntryPointChoice]
    /// False when a passing choice is flagged "replace default".
    public let keepsDefault: Bool

    public init(choices: [PerkEntryPointChoice]) {
        let activations = choices.filter { $0.activation != nil }
        immediate = activations.filter { $0.activation?.runsImmediately == true }
        offered = activations.filter { $0.activation?.runsImmediately != true }
        keepsDefault = !activations.contains { $0.activation?.replacesDefault == true }
    }

    public var isEmpty: Bool {
        immediate.isEmpty && offered.isEmpty
    }

    public var step: Step {
        if offered.isEmpty {
            return keepsDefault ? .defaultAction : .nothing
        }
        if offered.count == 1, !keepsDefault, let only = offered.first {
            return .single(only)
        }
        return .menu
    }
}
