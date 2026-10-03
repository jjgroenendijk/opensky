// The message box menu: one modal box at a time, the rest wait in order. A box
// from `Message.Show` carries the token its script waits on; closing it answers
// with the chosen button's MESG index. See docs/engine/messages.md#message-boxes.

import Foundation

nonisolated public struct MessageBoxRequest: Equatable, Sendable {
    public let title: String?
    public let text: String
    /// Never empty: `MessageTextBuilder` adds an OK button.
    public let buttons: [MessageBoxButton]
    /// The suspended `Message.Show` call, or nil for `Debug.MessageBox`.
    public let token: UInt64?

    public init(title: String?, text: String, buttons: [MessageBoxButton], token: UInt64?) {
        self.title = title
        self.text = text
        self.buttons = buttons.isEmpty
            ? [MessageBoxButton(index: 0, text: MessageTextBuilder.defaultButtonText)]
            : buttons
        self.token = token
    }
}

/// The answer a closed box gives its caller.
nonisolated public struct MessageBoxAnswer: Equatable, Sendable {
    public let token: UInt64?
    public let buttonIndex: Int
}

nonisolated public struct MessageBoxMenuModel: Equatable, Sendable {
    public private(set) var queue: [MessageBoxRequest] = []
    /// The highlighted row of the open box.
    public private(set) var selection = 0

    public init() {}

    public var current: MessageBoxRequest? {
        queue.first
    }

    public var isOpen: Bool {
        !queue.isEmpty
    }

    /// Queues a box. Returns true when it opened now, so the caller pauses the world.
    @discardableResult
    public mutating func enqueue(_ request: MessageBoxRequest) -> Bool {
        queue.append(request)
        if queue.count == 1 {
            selection = 0
        }
        return queue.count == 1
    }

    /// Moves the highlight by `step` rows, wrapping around.
    public mutating func moveSelection(by step: Int) {
        guard let count = current?.buttons.count, count > 0 else { return }
        selection = ((selection + step) % count + count) % count
    }

    public mutating func select(row: Int) {
        guard let count = current?.buttons.count, (0 ..< count).contains(row) else { return }
        selection = row
    }

    /// Picks the highlighted button, closes the box, and opens the next one.
    public mutating func accept() -> MessageBoxAnswer? {
        guard let box = current, box.buttons.indices.contains(selection) else { return nil }
        let answer = MessageBoxAnswer(token: box.token, buttonIndex: box.buttons[selection].index)
        queue.removeFirst()
        selection = 0
        return answer
    }

    /// Escape closes only a one-button box, as an OK. A question must be answered.
    public mutating func cancel() -> MessageBoxAnswer? {
        guard current?.buttons.count == 1 else { return nil }
        selection = 0
        return accept()
    }
}
