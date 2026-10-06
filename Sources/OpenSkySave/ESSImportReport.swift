// What an `.ess` import brought over and what it did not, per category, with reasons.
// The report is data, so the inspector, the load flow, and tests read the same thing.
// See docs/engine/ess-import.md.

import Foundation
import OpenSkyFormatsESS

nonisolated public struct ESSImportCategory: Equatable, Sendable {
    public let name: String
    public internal(set) var imported = 0
    /// Decoded but not brought over, by reason.
    public internal(set) var dropped: [String: Int] = [:]
    /// Present in the save but not decoded, by reason.
    public internal(set) var notDecoded: [String: Int] = [:]

    public init(name: String) {
        self.name = name
    }

    public var droppedCount: Int {
        dropped.values.reduce(0, +)
    }

    public var notDecodedCount: Int {
        notDecoded.values.reduce(0, +)
    }

    mutating func drop(_ reason: String, count: Int = 1) {
        guard count > 0 else { return }
        dropped[reason, default: 0] += count
    }

    mutating func skip(_ reason: String, count: Int = 1) {
        guard count > 0 else { return }
        notDecoded[reason, default: 0] += count
    }
}

nonisolated public struct ESSImportReport: Equatable, Sendable {
    /// Categories in a fixed order, so two imports of one save print the same.
    public internal(set) var categories: [ESSImportCategory]
    public let loadOrder: ESSLoadOrderComparison
    /// Running and suspended stacks, which are dropped, by the script they run.
    public internal(set) var droppedStacks: [String: Int] = [:]

    public static let categoryNames = [
        "globals", "clock", "player", "references", "inventories", "actors", "quests",
        "aliases", "dialogue", "scripts", "created forms"
    ]

    init(loadOrder: ESSLoadOrderComparison) {
        self.loadOrder = loadOrder
        categories = Self.categoryNames.map(ESSImportCategory.init(name:))
    }

    public func category(_ name: String) -> ESSImportCategory? {
        categories.first { $0.name == name }
    }

    mutating func update(_ name: String, _ change: (inout ESSImportCategory) -> Void) {
        guard let index = categories.firstIndex(where: { $0.name == name }) else { return }
        change(&categories[index])
    }

    /// The totals over every category, for a one-line notice.
    public var summary: String {
        let imported = categories.reduce(0) { $0 + $1.imported }
        let dropped = categories.reduce(0) { $0 + $1.droppedCount }
        let skipped = categories.reduce(0) { $0 + $1.notDecodedCount }
        return "\(imported) imported, \(dropped) dropped, \(skipped) not decoded"
    }

    /// One line per category, then the dropped and undecoded reasons indented.
    public var lines: [String] {
        var lines: [String] = []
        for category in categories {
            lines.append(
                "\(category.name): \(category.imported) imported, "
                    + "\(category.droppedCount) dropped, \(category.notDecodedCount) not decoded"
            )
            for (reason, count) in category.dropped.sorted(by: { $0.key < $1.key }) {
                lines.append("  dropped \(count): \(reason)")
            }
            for (reason, count) in category.notDecoded.sorted(by: { $0.key < $1.key }) {
                lines.append("  not decoded \(count): \(reason)")
            }
        }
        for (script, count) in droppedStacks.sorted(by: { $0.key < $1.key }) {
            lines.append("stack dropped \(count): \(script)")
        }
        if !loadOrder.missing.isEmpty {
            lines.append("plugins not loaded: \(loadOrder.missing.joined(separator: ", "))")
        }
        return lines
    }
}
