import Foundation
public import OpenSkyFormatsESM
import OpenSkyPhysics
import simd

/// One push, splash, or physics hit, kept for the readout.
nonisolated public enum ImpulseEvent: Equatable, Sendable {
    case knock(ReferenceKey, speed: Float, knockdown: Bool, cause: ImpulseCause)
    case push(ReferenceKey, impulse: Float, cause: ImpulseCause)
    case splash(SplashEvent)
    case physicsDamage(body: ReferenceKey, actor: ReferenceKey, damage: Float)
    case collision(BodyCollision)
}

/// What set a push off, for the readout.
nonisolated public enum ImpulseCause: String, Equatable, Sendable {
    case melee, ranged, explosion, projectile, water, debug
}
