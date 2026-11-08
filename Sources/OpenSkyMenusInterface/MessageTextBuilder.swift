import Foundation
import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData

/// One button a message box shows, with its index in the MESG, which is what
/// `Message.Show` returns.
nonisolated public struct MessageBoxButton: Equatable, Sendable {
    /// The OK button a box shows when the MESG defines none. `Show` returns 0 for it.
    public static let defaultText = "OK"
    public let index: Int
    public let text: String

    public init(index: Int, text: String) {
        self.index = index
        self.text = text
    }
}

/// The text and buttons of one MESG, ready to show.
nonisolated public struct BuiltMessage: Equatable, Sendable {
    public let title: String?
    public let text: String
    public let buttons: [MessageBoxButton]
    public let isMessageBox: Bool
    /// TNAM seconds, for a notification.
    public let displaySeconds: Float?

    public init(
        title: String?,
        text: String,
        buttons: [MessageBoxButton],
        isMessageBox: Bool,
        displaySeconds: Float? = nil
    ) {
        self.title = title
        self.text = text
        self.buttons = buttons
        self.isMessageBox = isMessageBox
        self.displaySeconds = displaySeconds
    }
}
