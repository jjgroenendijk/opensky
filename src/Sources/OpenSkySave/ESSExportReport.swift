// What an `.ess` export wrote and what it left out, per category, with reasons. The
// categories match the import report's, so the two read side by side.
// See docs/engine/ess-export.md.

import Foundation

nonisolated public struct ESSExportCategory: Equatable, Sendable {
    public let name: String
    public internal(set) var written = 0
    /// Left out, by reason.
    public internal(set) var dropped: [String: Int] = [:]

    public var droppedCount: Int {
        dropped.values.reduce(0, +)
    }

    mutating func drop(_ reason: String, count: Int = 1) {
        guard count > 0 else { return }
        dropped[reason, default: 0] += count
    }
}

nonisolated public struct ESSExportReport: Equatable, Sendable {
    public internal(set) var categories: [ESSExportCategory]

    public static let categoryNames = [
        "globals", "clock", "player", "references", "inventories", "quests", "aliases",
        "dialogue", "scripts", "created forms", "other state"
    ]

    init() {
        categories = Self.categoryNames.map { ESSExportCategory(name: $0) }
    }

    public func category(_ name: String) -> ESSExportCategory? {
        categories.first { $0.name == name }
    }

    mutating func update(_ name: String, _ change: (inout ESSExportCategory) -> Void) {
        guard let index = categories.firstIndex(where: { $0.name == name }) else { return }
        change(&categories[index])
    }

    public var summary: String {
        let written = categories.reduce(0) { $0 + $1.written }
        let dropped = categories.reduce(0) { $0 + $1.droppedCount }
        return "\(written) written, \(dropped) left out"
    }

    /// The summary, then one line per category with anything in it, then its reasons.
    public var lines: [String] {
        var lines = [summary]
        for category in categories where category.written + category.droppedCount > 0 {
            lines.append("\(category.name): \(category.written) written, "
                + "\(category.droppedCount) left out")
            for (reason, count) in category.dropped.sorted(by: { $0.key < $1.key }) {
                lines.append("  left out \(count): \(reason)")
            }
        }
        return lines
    }
}
