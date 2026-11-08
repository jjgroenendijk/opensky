import Foundation
public import OpenSkyFormatsESM

/// One trap touching one actor, as the trap events report it.
nonisolated public struct PapyrusTrapHit: Equatable, Sendable {
    public let target: ReferenceKey
    public let velocity: SIMD3<Float>
    public let position: SIMD3<Float>
    public let initial: Bool

    public init(
        target: ReferenceKey, velocity: SIMD3<Float>, position: SIMD3<Float>, initial: Bool
    ) {
        self.target = target
        self.velocity = velocity
        self.position = position
        self.initial = initial
    }
}
