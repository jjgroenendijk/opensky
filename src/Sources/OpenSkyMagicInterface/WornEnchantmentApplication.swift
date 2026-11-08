import Foundation
public import OpenSkyFormatsESM
import OpenSkyGameData

/// What one reconciliation did.
nonisolated public struct WornEnchantmentReport: Equatable, Sendable {
    /// Items whose effects were applied this time, ascending.
    public let applied: [FormID]
    /// Items whose effects were taken back off, ascending.
    public let removed: [FormID]
    /// Constant effects stored across every newly worn item.
    public let storedCount: Int
    /// Effects dispelled across every item that came off.
    public let dispelledCount: Int

    public static let none = WornEnchantmentReport(
        applied: [], removed: [], storedCount: 0, dispelledCount: 0
    )

    /// Whether anything moved, which is what tells a caller to refresh a readout.
    public var didChange: Bool {
        !applied.isEmpty || !removed.isEmpty
    }

    public init(
        applied: [FormID],
        removed: [FormID],
        storedCount: Int,
        dispelledCount: Int
    ) {
        self.applied = applied
        self.removed = removed
        self.storedCount = storedCount
        self.dispelledCount = dispelledCount
    }
}
