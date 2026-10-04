// interface\controls\pc\controlmap.txt: input contexts of user events, each with
// its keyboard, mouse, and gamepad inputs and its remap flags. The file's own
// header comment names the columns. Layout: docs/formats/controlmap.md.

import Foundation

nonisolated public enum ControlMapError: Error, Equatable, Sendable {
    case notText
    case malformedLine(line: Int, reason: String)
}

/// One input in a device column.
nonisolated public enum ControlInput: Equatable, Hashable, Sendable {
    /// A device code: a DirectInput scan code, a mouse button, or a gamepad button.
    case code(UInt32)
    /// Every code held at once, such as `0x1d+0xb7`.
    case chord([UInt32])
    /// The same column's inputs of `event` in context number `context` (`!0,Activate`).
    case reference(context: Int, event: String)
}

nonisolated public struct ControlMapEvent: Equatable, Sendable {
    public let name: String
    /// An empty list means unmapped (`0xff`).
    public let keyboard: [ControlInput]
    public let mouse: [ControlInput]
    public let gamepad: [ControlInput]
    public let remappableKeyboard: Bool
}

nonisolated public struct ControlMapContext: Equatable, Sendable {
    /// The comment above the context's first event, such as `Main Gameplay`.
    public let name: String
    public let events: [ControlMapEvent]

    public func event(named name: String) -> ControlMapEvent? {
        events.first { $0.name == name }
    }
}

nonisolated public struct ControlMapFile: Equatable, Sendable {
    public static let unmapped: UInt32 = 0xFF
    /// The VFS key of the vanilla file.
    public static let path = "interface\\controls\\pc\\controlmap.txt"

    public let contexts: [ControlMapContext]

    public func context(named name: String) -> ControlMapContext? {
        contexts.first { $0.name == name }
    }

    /// Lines are tab separated; a run of tabs is one separator. A blank line
    /// starts a new context, and `//` starts a comment.
    public init(data: Data) throws(ControlMapError) {
        guard
            let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
        else { throw .notText }
        var contexts: [ControlMapContext] = []
        var events: [ControlMapEvent] = []
        var lastComment = ""
        var name: String?
        func close() {
            if !events.isEmpty {
                contexts.append(ControlMapContext(
                    name: name ?? "Context \(contexts.count)",
                    events: events
                ))
            }
            events = []
            name = nil
        }
        for (offset, raw) in text.split(
            omittingEmptySubsequences: false,
            whereSeparator: \.isNewline
        )
        .enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                close()
                continue
            }
            if line.hasPrefix("//") {
                let comment = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
                if !comment.isEmpty {
                    lastComment = comment
                }
                continue
            }
            if events.isEmpty, name == nil {
                name = lastComment
            }
            try events.append(Self.event(line, number: offset + 1))
        }
        close()
        self.contexts = contexts
    }

    private static func event(
        _ line: String,
        number: Int
    ) throws(ControlMapError) -> ControlMapEvent {
        let fields = line.split(separator: "\t").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard fields.count >= 7 else {
            throw .malformedLine(
                line: number,
                reason: "\(fields.count) fields, expected at least 7"
            )
        }
        func flag(_ index: Int) throws(ControlMapError) -> Bool {
            switch fields[index] {
            case "0": return false
            case "1": return true
            default: throw .malformedLine(line: number, reason: "remap flag \(fields[index])")
            }
        }
        // The mouse and gamepad flags and the optional group flags are checked, not kept.
        _ = try (flag(5), flag(6))
        if fields.count > 7, hex(fields[7]) == nil {
            throw .malformedLine(line: number, reason: "group flags \(fields[7])")
        }
        return try ControlMapEvent(
            name: fields[0],
            keyboard: inputs(fields[1], line: number),
            mouse: inputs(fields[2], line: number),
            gamepad: inputs(fields[3], line: number),
            remappableKeyboard: flag(4)
        )
    }

    /// `0xff`, `0x11`, `0x02,0x4f`, `0x1d+0xb7`, or `!0,Activate,!0,Pause`.
    static func inputs(_ field: String, line: Int) throws(ControlMapError) -> [ControlInput] {
        var result: [ControlInput] = []
        var tokens = field.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }[...]
        while let token = tokens.popFirst() {
            if token.hasPrefix("!") {
                guard
                    let context = Int(token.dropFirst()), let event = tokens.popFirst(),
                    !event.isEmpty
                else { throw .malformedLine(line: line, reason: "reference \(token)") }
                result.append(.reference(context: context, event: event))
                continue
            }
            let parts = token.split(separator: "+").map(String.init)
            let codes = parts.compactMap(hex)
            guard codes.count == parts.count, !codes.isEmpty else {
                throw .malformedLine(line: line, reason: "input \(token)")
            }
            if codes.count > 1 {
                result.append(.chord(codes))
            } else if codes[0] != unmapped {
                result.append(.code(codes[0]))
            }
        }
        return result
    }

    static func hex(_ text: String) -> UInt32? {
        let lowered = text.lowercased()
        if lowered.hasPrefix("0x") {
            return UInt32(lowered.dropFirst(2), radix: 16)
        }
        return UInt32(lowered)
    }
}

nonisolated public enum ControlDevice: Sendable {
    case keyboard, mouse, gamepad
}

nonisolated extension ControlMapFile {
    /// The plain codes an event answers to on one device, with references followed.
    /// A chord is left out: it needs several keys and is reported on its own.
    public func codes(of event: String, in context: Int, device: ControlDevice) -> [UInt32] {
        var seen: Set<String> = []
        return codes(of: event, in: context, device: device, seen: &seen)
    }

    private func codes(
        of event: String, in context: Int, device: ControlDevice, seen: inout Set<String>
    ) -> [UInt32] {
        guard
            contexts.indices.contains(context),
            seen.insert("\(context)|\(event)").inserted,
            let entry = contexts[context].event(named: event)
        else { return [] }
        let column = switch device {
        case .keyboard: entry.keyboard
        case .mouse: entry.mouse
        case .gamepad: entry.gamepad
        }
        return column.flatMap { input -> [UInt32] in
            switch input {
            case let .code(code): [code]
            case .chord: []
            case let .reference(target, name): codes(
                    of: name,
                    in: target,
                    device: device,
                    seen: &seen
                )
            }
        }
    }
}
