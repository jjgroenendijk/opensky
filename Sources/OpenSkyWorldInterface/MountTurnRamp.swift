import Foundation

nonisolated public struct MountTurnRamp: Equatable, Sendable {
    /// A wanted turn below this, in radians, counts as no turn: the horse faces its goal.
    public static let turnThreshold: Float = 0.001

    /// Radians a second the horse turns at now.
    public package(set) var rate: Float = 0

    public init() {}
}
