import Foundation

nonisolated public struct MessageBoxRequest: Equatable, Sendable {
    public let title: String?
    public let text: String
    /// Never empty: the init adds an OK button.
    public let buttons: [MessageBoxButton]
    /// The suspended `Message.Show` call, or nil for `Debug.MessageBox`.
    public let token: UInt64?

    public init(title: String?, text: String, buttons: [MessageBoxButton], token: UInt64?) {
        self.title = title
        self.text = text
        self.buttons = buttons.isEmpty
            ? [MessageBoxButton(index: 0, text: MessageBoxButton.defaultText)]
            : buttons
        self.token = token
    }
}
