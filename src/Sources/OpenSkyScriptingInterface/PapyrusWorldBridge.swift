import Foundation
import OpenSkyFormatsESM
import OpenSkyInventoryInterface
import OpenSkyWorldState

/// What one activation did, returned by both
/// `PapyrusWorldBridge.activate(_:by:togglesOpen:)` and
/// `PapyrusWorldRuntime.queueOnActivate(target:activator:)`. The queue-only
/// caller always reports `recorded == false`, because it writes no state.
nonisolated public struct PapyrusActivationOutcome: Equatable, Sendable {
    /// True when the `ReferenceActivationState` write changed stored state.
    public let recorded: Bool
    /// `OnActivate` events enqueued on the target's script instances.
    public let queuedEvents: Int
    /// True when the recursion cap refused to queue anything.
    public let cappedByRecursion: Bool

    public static let none = PapyrusActivationOutcome(
        recorded: false, queuedEvents: 0, cappedByRecursion: false
    )

    public init(
        recorded: Bool,
        queuedEvents: Int,
        cappedByRecursion: Bool
    ) {
        self.recorded = recorded
        self.queuedEvents = queuedEvents
        self.cappedByRecursion = cappedByRecursion
    }
}
