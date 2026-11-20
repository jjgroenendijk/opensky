// The skills menu's questions: the engine shows each one as a message box over the menu.
// See docs/engine/skills-menu.md#the-two-questions.

import Foundation
import OpenSkyGameData
import OpenSkyMenusInterface
import OpenSkyProgressionInterface

nonisolated extension SkillsMenuModel {
    /// The open question, which the engine shows as a message box over the menu.
    public var question: ConfirmationModel? {
        switch page {
        case let .legendary(confirmation), let .legendaryAgain(confirmation),
             let .perkConfirm(confirmation), let .attributeConfirm(_, confirmation):
            confirmation
        case .levelUp, .skills, .perks:
            nil
        }
    }

    /// The button the message box returned, as a key press on the open question.
    public mutating func answer(_ button: Int) -> Action? {
        guard var confirmation = question else { return nil }
        confirmation.select(button)
        switch page {
        case .legendary: page = .legendary(confirmation)
        case .legendaryAgain: page = .legendaryAgain(confirmation)
        case .perkConfirm: page = .perkConfirm(confirmation)
        case let .attributeConfirm(kind, _): page = .attributeConfirm(kind, confirmation)
        case .levelUp, .skills, .perks: return nil
        }
        return handle(.button(.accept))
    }

    mutating func handleAttributeConfirm(
        _ event: MenuInputEvent, kind: ActorValueKind, _ confirmation: ConfirmationModel
    ) -> Action? {
        var confirmation = confirmation
        switch confirmation.handle(event) {
        case nil:
            page = .attributeConfirm(kind, confirmation)
            return nil
        case .chose(0):
            page = .levelUp
            return .chooseAttribute(kind)
        case .chose, .cancelled:
            page = .levelUp
            return nil
        }
    }

    mutating func askAttribute() {
        let kind = selectedAttribute
        let name = kind.rawValue.capitalized
        page = .attributeConfirm(kind, ConfirmationModel(
            question: texts[.attributeConfirm].replacingOccurrences(of: "%s", with: name),
            options: [texts[.ok], texts[.cancel]]
        ))
    }
}
