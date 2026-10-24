// A trap world that records what the trap natives asked of it.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyScripting
import OpenSkyWorldState

final class FakeTrapWorld: PapyrusTrapWorldBridge {
    struct Placed {
        let base: ReferenceKey
        let anchor: ReferenceKey
        let count: Int
    }

    struct Push {
        let source: ReferenceKey
        let direction: SIMD3<Float>?
        let speed: Float
    }

    struct Shot {
        let weapon: ReferenceKey
        let source: ReferenceKey
        let ammunition: ReferenceKey?
    }

    var placed: [Placed] = []
    var impulses: [(impulse: SIMD3<Float>, reference: ReferenceKey)] = []
    var pushes: [Push] = []
    var staggers: [(actor: ReferenceKey, magnitude: Float)] = []
    var motionTypes: [ReferenceKey: ReferenceMotionType] = [:]
    var resets: [(reference: ReferenceKey, target: ReferenceKey?)] = []
    var shots: [Shot] = []
    /// False answers `Reset` as an actor would.
    var resetsReferences = true

    func placeAtMe(_ base: ReferenceKey, at anchor: ReferenceKey, count: Int) -> ReferenceKey? {
        placed.append(Placed(base: base, anchor: anchor, count: count))
        return .generated(42)
    }

    func applyImpulse(_ impulse: SIMD3<Float>, to reference: ReferenceKey) -> Bool {
        impulses.append((impulse, reference))
        return true
    }

    func pushActor(
        _: ReferenceKey, awayFrom source: ReferenceKey,
        along direction: SIMD3<Float>?, speed: Float
    ) -> Bool {
        pushes.append(Push(source: source, direction: direction, speed: speed))
        return true
    }

    func staggerActor(_ actor: ReferenceKey, magnitude: Float) -> Bool {
        staggers.append((actor, magnitude))
        return true
    }

    func setMotionType(_ motionType: ReferenceMotionType, of reference: ReferenceKey) -> Bool {
        motionTypes[reference] = motionType
        return true
    }

    func resetReference(_ reference: ReferenceKey, to target: ReferenceKey?) -> Bool {
        guard resetsReferences else { return false }
        resets.append((reference, target))
        return true
    }

    func fireWeapon(
        _ weapon: ReferenceKey, from source: ReferenceKey, ammunition: ReferenceKey?
    ) -> Bool {
        shots.append(Shot(weapon: weapon, source: source, ammunition: ammunition))
        return true
    }
}
