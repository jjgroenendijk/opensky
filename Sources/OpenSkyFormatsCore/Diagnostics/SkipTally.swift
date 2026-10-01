/// A skip reason with a printable name, so a tally can rank it.
nonisolated public protocol SkipTallyKind: Hashable, Sendable {
    var name: String { get }
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

    public mutating func merge(_ other: Self) {
        for (kind, count) in other.counts {
            note(kind, count: count)
        }
    }
}

nonisolated extension SkipTally where Kind: SkipTallyKind {
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
