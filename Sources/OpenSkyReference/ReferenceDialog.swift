// A message box open in the Windows game, as the bridge plugin reports it.

import Foundation

nonisolated public struct ReferenceDialog: Codable, Equatable, Sendable {
    public var text: String
    public var buttons: [String]

    public init(text: String, buttons: [String]) {
        self.text = text
        self.buttons = buttons
    }

    /// The index of `button`, given as a number or as a button's text in any case.
    public func buttonIndex(of button: String) -> Int? {
        if let index = Int(button) {
            return buttons.indices.contains(index) ? index : nil
        }
        let wanted = button.trimmingCharacters(in: .whitespaces).lowercased()
        return buttons.firstIndex { $0.trimmingCharacters(in: .whitespaces).lowercased() == wanted }
    }
}
