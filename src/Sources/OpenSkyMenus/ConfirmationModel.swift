// A yes or no question shown over a menu page, such as "Delete this save?".

import Foundation
import OpenSkyMenusInterface

nonisolated enum ConfirmationChoice: Equatable, Sendable {
    case chose(Int)
    case cancelled
}

nonisolated public struct ConfirmationModel: Equatable, Sendable {
    let question: String
    let options: [String]
    private(set) var selectedIndex: Int

    /// Starts on the last option, so a stray accept never confirms by accident.
    init(question: String, options: [String] = ["Yes", "No"]) {
        self.question = question
        self.options = options.isEmpty ? ["OK"] : options
        selectedIndex = self.options.count - 1
    }

    mutating func handle(_ event: MenuInputEvent) -> ConfirmationChoice? {
        switch event {
        case .move(.up), .move(.left):
            selectedIndex = (selectedIndex + options.count - 1) % options.count
        case .move(.down), .move(.right):
            selectedIndex = (selectedIndex + 1) % options.count
        case .button(.accept):
            return .chose(selectedIndex)
        case .button(.cancel):
            return .cancelled
        case .button(.xButton), .button(.yButton), .pointer, .release:
            break
        }
        return nil
    }
}
