nonisolated public struct MessageBoxPresentation: Equatable, Sendable {
    public let request: MessageBoxRequest
    public let selection: Int

    public init(request: MessageBoxRequest, selection: Int) {
        self.request = request
        self.selection = selection
    }

    public static let hint = "W/S: choose   E or Enter: accept   Esc: close a one-button box"
}
