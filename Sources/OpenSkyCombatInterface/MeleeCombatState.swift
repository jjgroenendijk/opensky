import Foundation
import OpenSkyActorsInterface

/// Where a swing is. `windup` opens at `attackStart`, `swinging` at
/// `preHitFrame`, `contact` at `HitFrame`, and `recovery` runs until the attack
/// state ends. The hit window is `contact` alone.
nonisolated public enum MeleeAttackPhase: String, Equatable, Sendable, CaseIterable {
    case idle
    case windup
    case swinging
    case contact
    case recovery

    /// Whether a swing is in progress at all, which is what `IsAttacking`
    /// reports to the graph.
    public var isAttacking: Bool {
        self != .idle
    }
}
