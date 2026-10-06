/// A skip reason with a printable name, so a tally can rank it.
nonisolated public protocol SkipTallyKind: Hashable, Sendable {
    var name: String { get }
}

/// A tally a report can rank without knowing its reason type.
nonisolated public protocol RankedSkipReport: Sendable {
    /// Most frequent first; equal counts sort by name.
    var ranked: [(name: String, count: Int)] { get }
}

nonisolated extension RankedSkipReport {
    /// Ranks counts kept in separate per-reason maps, each name led by `prefix`.
    public static func rank(
        _ groups: [(prefix: String, counts: [some CustomStringConvertible: Int])]
    ) -> [(name: String, count: Int)] {
        var entries: [(name: String, count: Int)] = []
        for group in groups {
            for (key, count) in group.counts {
                entries.append((name: "\(group.prefix) \(key)", count: count))
            }
        }
        return entries.sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }
}

/// Reason-tagged count of what a decode or fill pass skipped. A census asserts
/// against it, and a readout prints `ranked`.
nonisolated public struct SkipTally<Kind: Hashable & Sendable>: Equatable, Sendable {
    public private(set) var counts: [Kind: Int] = [:]

    public init() {}

    public var total: Int {
        counts.values.reduce(0, +)
    }

    public var isEmpty: Bool {
        counts.isEmpty
    }

    public mutating func note(_ kind: Kind, count: Int = 1) {
        counts[kind, default: 0] += count
    }

    /// Takes one count back, for an item a second decoder read after all.
    public mutating func unnote(_ kind: Kind) {
        guard let count = counts[kind] else { return }
        counts[kind] = count > 1 ? count - 1 : nil
    }

    public mutating func merge(_ other: Self) {
        for (kind, count) in other.counts {
            note(kind, count: count)
        }
    }
}

nonisolated extension SkipTally: RankedSkipReport where Kind: SkipTallyKind {
    /// Most frequent first; equal counts sort by name.
    public var ranked: [(name: String, count: Int)] {
        counts
            .sorted {
                $0.value == $1.value
                    ? $0.key.name < $1.key.name
                    : $0.value > $1.value
            }
            .map { ($0.key.name, $0.value) }
    }
}
