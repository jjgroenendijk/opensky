// A yes or no question shown over a menu page, such as "Delete this save?".

import Foundation

nonisolated public enum ConfirmationChoice: Equatable, Sendable {
    case chose(Int)
    case cancelled
}

nonisolated public struct ConfirmationModel: Equatable, Sendable {
    public let question: String
    public let options: [String]
    public private(set) var selectedIndex: Int

    /// Starts on the last option, so a stray accept never confirms by accident.
    public init(question: String, options: [String] = ["Yes", "No"]) {
        self.question = question
        self.options = options.isEmpty ? ["OK"] : options
        selectedIndex = self.options.count - 1
    }

    public mutating func handle(_ event: MenuInputEvent) -> ConfirmationChoice? {
        switch event {
        case .move(.up), .move(.left):
            selectedIndex = (selectedIndex + options.count - 1) % options.count
        case .move(.down), .move(.right):
            selectedIndex = (selectedIndex + 1) % options.count
        case .button(.accept):
            return .chose(selectedIndex)
        case .button(.cancel):
            return .cancelled
        case .pointer, .release:
            break
        }
        return nil
    }
}
