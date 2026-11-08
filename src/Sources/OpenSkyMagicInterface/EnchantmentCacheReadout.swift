import Foundation

/// One reading of the profile cache.
nonisolated public struct EnchantmentCacheReadout: Equatable, Sendable {
    public let itemCount: Int
    public let resolvedCount: Int
    public let reuseCount: Int

    /// Nothing asked for yet, which is also what a session with no game data
    /// reads.
    public static let empty = EnchantmentCacheReadout(itemCount: 0, resolvedCount: 0, reuseCount: 0)

    /// One line for a readout.
    public var describedLine: String {
        "Enchantment cache: \(itemCount) item(s), \(resolvedCount) resolved, "
            + "\(reuseCount) reused"
    }

    public init(itemCount: Int, resolvedCount: Int, reuseCount: Int) {
        self.itemCount = itemCount
        self.resolvedCount = resolvedCount
        self.reuseCount = reuseCount
    }
}
