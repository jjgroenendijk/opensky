/// Puts a list in `ReferenceKey` order, and sorts again only when the keys change.
/// Per-frame rosters keep the same members for many frames, so most calls only
/// compare the keys and reuse the last order.
nonisolated public struct ReferenceKeyOrder: Sendable {
    private var keys: [ReferenceKey] = []
    /// Indices into the input, in ascending key order.
    private var permutation: [Int] = []

    public init() {}

    public mutating func sorted<Element>(
        _ elements: [Element],
        by key: (Element) -> ReferenceKey
    ) -> [Element] {
        let current = elements.map(key)
        if current != keys {
            keys = current
            permutation = current.indices.sorted { (current[$0], $0) < (current[$1], $1) }
        }
        return permutation.map { elements[$0] }
    }

    /// `elements` unchanged when already in key order, else sorted by key. The
    /// check is one pass, so a caller that keeps its list ordered pays no sort.
    public static func ascending<Element>(
        _ elements: [Element],
        by key: (Element) -> ReferenceKey
    ) -> [Element] {
        let isAscending = zip(elements, elements.dropFirst()).allSatisfy { key($0) <= key($1) }
        return isAscending ? elements : elements.sorted { key($0) < key($1) }
    }
}
