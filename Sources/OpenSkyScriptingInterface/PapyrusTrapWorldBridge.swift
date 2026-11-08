import Foundation
public import OpenSkyFormatsESM
public import OpenSkyWorldState
import simd

/// What the trap natives reach in the running game. The app answers it.
public protocol PapyrusTrapWorldBridge: AnyObject {
    /// Places `count` copies of the base form `base` at `anchor`. Returns the last
    /// placed reference, or nil when the base cannot be placed here.
    func placeAtMe(_ base: ReferenceKey, at anchor: ReferenceKey, count: Int) -> ReferenceKey?
    /// Pushes a simulated body. False when `reference` has no dynamic body.
    func applyImpulse(_ impulse: SIMD3<Float>, to reference: ReferenceKey) -> Bool
    /// Knocks an actor back at `speed` units per second, along `direction` or, when
    /// it is nil, away from `source`. A negative speed pulls. False when the actor
    /// cannot be pushed.
    func pushActor(
        _ actor: ReferenceKey, awayFrom source: ReferenceKey,
        along direction: SIMD3<Float>?, speed: Float
    ) -> Bool
    /// Knocks an actor down as a ragdoll, away from `source` at `magnitude` Havok metres a
    /// second; a negative magnitude pulls. False when nothing knocked it.
    func knockDownActor(_ actor: ReferenceKey, awayFrom source: ReferenceKey, magnitude: Float)
        -> Bool
    /// Staggers an actor by `magnitude`, 0 to 1. False when it cannot stagger.
    func staggerActor(_ actor: ReferenceKey, magnitude: Float) -> Bool
    /// Sets whether a reference's collision simulates. False when it has no cell.
    func setMotionType(_ motionType: ReferenceMotionType, of reference: ReferenceKey) -> Bool
    /// Puts an object back where its plugin placed it, or at `target`. False for an actor.
    func resetReference(_ reference: ReferenceKey, to target: ReferenceKey?) -> Bool
    /// Fires `weapon` with `ammunition` from `source`, along its facing. False when
    /// nothing flies.
    func fireWeapon(
        _ weapon: ReferenceKey, from source: ReferenceKey, ammunition: ReferenceKey?
    ) -> Bool
}
