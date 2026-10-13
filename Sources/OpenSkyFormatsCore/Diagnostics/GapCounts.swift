// Uses per item for a gap census: what the game data uses, split by whether the engine
// handles it. `openskycli gaps` prints the split.

import Foundation

nonisolated public struct GapCounts: Equatable, Sendable {
    public private(set) var uses: [String: Int] = [:]

    public init() {}

    public var total: Int {
        uses.values.reduce(0, +)
    }

    public mutating func add(_ name: String, count: Int = 1) {
        uses[name, default: 0] += count
    }

    /// Distinct items `handled` accepts.
    public func done(where handled: (String) -> Bool) -> Int {
        uses.keys.count(where: handled)
    }

    /// Items `handled` rejects, most used first.
    public func left(where handled: (String) -> Bool) -> [(name: String, count: Int)] {
        Self.ranked(uses.filter { !handled($0.key) })
    }

    /// Most used first; equal counts sort by name.
    public static func ranked(_ counts: [String: Int]) -> [(name: String, count: Int)] {
        counts.map { (name: $0.key, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }

    /// A failure message with each number replaced by `#`, so one kind of failure is
    /// one row however many blocks or offsets it names.
    public static func failureKind(_ message: String) -> String {
        message.replacing(/[0-9]+/, with: "#")
    }
}
