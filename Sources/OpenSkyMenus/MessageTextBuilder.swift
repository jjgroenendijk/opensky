// Builds what a MESG shows: its text with the `Message.Show` numbers and alias
// tags filled in, and its visible buttons. Rules and sources:
// docs/engine/messages.md#building-the-text.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData

/// One button a message box shows, with its index in the MESG, which is what
/// `Message.Show` returns.
nonisolated public struct MessageBoxButton: Equatable, Sendable {
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

nonisolated public struct MessageTextBuilder: Sendable {
    /// The OK button a box shows when the MESG defines none. `Show` returns 0 for it.
    public static let defaultButtonText = "OK"
    /// Message boxes have a 1023-character limit (Creation Kit wiki, Message).
    public static let maximumLength = 1023

    public let strings: LocalizedStrings?
    public let naming: QuestAliasNaming

    public init(strings: LocalizedStrings?, naming: QuestAliasNaming = .none) {
        self.strings = strings
        self.naming = naming
    }

    /// `message` with `arguments` and alias tags filled. `quest` is the
    /// message's QNAM owner, whose aliases the tags name.
    public func build(
        _ message: GameMessage,
        arguments: [Float] = [],
        quest: Quest? = nil,
        buttonVisible: (GameMessage.Button) -> Bool = { _ in true }
    ) -> BuiltMessage {
        let raw = JournalMenuModel
            .text(message.description, kind: .dlstrings, strings: strings) ?? ""
        var text = MessageFormat.format(raw, arguments: arguments)
        if let quest {
            text = naming.substituting(text, in: quest)
        }
        return BuiltMessage(
            title: JournalMenuModel.text(message.name, kind: .strings, strings: strings),
            text: String(text.prefix(Self.maximumLength)),
            buttons: message.isMessageBox ? buttons(of: message, visible: buttonVisible) : [],
            isMessageBox: message.isMessageBox,
            displaySeconds: message.displayTime.map { Float($0) }
        )
    }

    /// The buttons whose conditions pass, each keeping its MESG index. A box
    /// with no buttons, or none visible, gets one OK button at index 0.
    public func buttons(
        of message: GameMessage,
        visible: (GameMessage.Button) -> Bool
    ) -> [MessageBoxButton] {
        let shown = message.buttons.enumerated().compactMap { index, button -> MessageBoxButton? in
            guard visible(button) else { return nil }
            let text = JournalMenuModel.text(button.text, kind: .strings, strings: strings)
            return MessageBoxButton(index: index, text: text ?? "")
        }
        return shown.isEmpty ? [MessageBoxButton(index: 0, text: Self.defaultButtonText)] : shown
    }

    /// The button check for one condition context: every CTDA must pass.
    public static func conditionCheck(
        _ evaluator: ConditionEvaluator
    ) -> (GameMessage.Button) -> Bool {
        { button in
            var copy = evaluator
            return copy.evaluate(button.conditions).isTrue
        }
    }
}

/// The `%[flags][width][.precision]f` tokens of `Message.Show`, and `%%`.
nonisolated public enum MessageFormat {
    /// Fills the tokens in order from `arguments`; a missing argument is 0, as
    /// `Show`'s defaults are. A `%` that starts no token is kept.
    public static func format(_ text: String, arguments: [Float]) -> String {
        guard text.contains("%") else { return text }
        var result = ""
        var next = 0
        var rest = Substring(text)
        while let percent = rest.firstIndex(of: "%") {
            result += rest[..<percent]
            let after = rest[rest.index(after: percent)...]
            if after.first == "%" {
                result.append("%")
                rest = after.dropFirst()
                continue
            }
            guard let token = Token(after) else {
                result.append("%")
                rest = after
                continue
            }
            let value = next < arguments.count ? arguments[next] : 0
            next += 1
            result += token.render(value)
            rest = after.dropFirst(token.length)
        }
        return result + rest
    }

    /// True when text still holds a `<...>` tag or a `%` token after building.
    public static func hasUnresolvedToken(_ text: String) -> Bool {
        if let open = text.firstIndex(of: "<"), text[open...].contains(">") {
            return true
        }
        return format(text, arguments: []) != text.replacingOccurrences(of: "%%", with: "%")
    }

    private struct Token {
        let flags: String
        let width: Int?
        let precision: Int?
        let length: Int

        init?(_ text: Substring) {
            let flags = text.prefix { "-+0 #".contains($0) }
            var rest = text.dropFirst(flags.count)
            let width = rest.prefix(while: \.isNumber)
            rest = rest.dropFirst(width.count)
            var precision: Int?
            var precisionLength = 0
            if rest.first == "." {
                let digits = rest.dropFirst().prefix(while: \.isNumber)
                precision = Int(digits) ?? 0
                precisionLength = 1 + digits.count
                rest = rest.dropFirst(precisionLength)
            }
            guard rest.first == "f" else { return nil }
            self.flags = String(flags)
            self.width = Int(width)
            self.precision = precision
            length = flags.count + width.count + precisionLength + 1
        }

        /// With no precision the wiki shows "%f" of 5 as "5.0" and of 1.1 as
        /// "1.1": six digits with trailing zeros dropped, one kept.
        func render(_ value: Float) -> String {
            let digits = precision ?? 6
            var body = String(format: "%.\(digits)f", Double(value))
            if precision == nil, body.contains(".") {
                while body.hasSuffix("0"), !body.hasSuffix(".0") {
                    body.removeLast()
                }
            }
            if flags.contains("#"), !body.contains(".") {
                body += "."
            }
            if flags.contains("+"), value >= 0 {
                body = "+" + body
            } else if flags.contains(" "), value >= 0 {
                body = " " + body
            }
            guard let width, body.count < width else { return body }
            let padding = width - body.count
            if flags.contains("-") {
                return body + String(repeating: " ", count: padding)
            }
            guard flags.contains("0") else {
                return String(repeating: " ", count: padding) + body
            }
            let sign = body.first
                .map { "+- ".contains($0) } == true ? String(body.removeFirst()) : ""
            return sign + String(repeating: "0", count: padding) + body
        }
    }
}
