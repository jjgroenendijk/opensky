import Foundation
public import OpenSkyFormatsESM
import OpenSkyPhysics

/// One landing and what it did, for `state` reads.
nonisolated public struct FallOutcome: Equatable, Sendable {
    public let actor: ReferenceKey
    public let height: Float
    public let speed: Float
    public let damage: Float

    public init(actor: ReferenceKey, height: Float, speed: Float, damage: Float) {
        self.actor = actor
        self.height = height
        self.speed = speed
        self.damage = damage
    }
}
