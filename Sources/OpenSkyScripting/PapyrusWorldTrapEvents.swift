// Trap contact events: `OnTrapHitStart`, `OnTrapHit`, and `OnTrapHitStop` on the trap's
// own scripts (<https://ck.uesp.net/wiki/OnTrapHitStart_-_ObjectReference>).

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

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

extension PapyrusWorldRuntime {
    /// `Motion_Keyframed`: a trap's graph moves it, not Havok.
    static let keyframedMotionType: Int32 = 4

    /// Whether a script on `trap` listens for any trap event, so other objects skip contact.
    public func handlesTrapHits(on trap: ReferenceKey) -> Bool {
        let names = [
            PapyrusEngineEvents.onTrapHitStart, PapyrusEngineEvents.onTrapHit,
            PapyrusEngineEvents.onTrapHitStop
        ]
        return instanceKeys(on: trap).contains { key in
            names.contains { handlesEvent($0, key: key) }
        }
    }

    /// The first contact queues `OnTrapHitStart` and `OnTrapHit`; a repeat only `OnTrapHit`.
    @discardableResult
    public func queueTrapHit(_ hit: PapyrusTrapHit, on trap: ReferenceKey) -> Int {
        let arguments: [PapyrusValue] = [
            .object(objectHandle(for: hit.target)),
            .float(hit.velocity.x), .float(hit.velocity.y), .float(hit.velocity.z),
            .float(hit.position.x), .float(hit.position.y), .float(hit.position.z),
            .integer(0), .boolean(hit.initial), .integer(Self.keyframedMotionType)
        ]
        var queued = 0
        if hit.initial {
            queued += queueActorEvent(
                PapyrusEngineEvents.onTrapHitStart, on: trap, arguments: arguments
            )
        }
        return queued + queueActorEvent(
            PapyrusEngineEvents.onTrapHit,
            on: trap,
            arguments: arguments
        )
    }

    /// `OnTrapHitStop(ObjectReference akTarget)`.
    @discardableResult
    public func queueTrapHitStop(target: ReferenceKey, on trap: ReferenceKey) -> Int {
        queueActorEvent(
            PapyrusEngineEvents.onTrapHitStop, on: trap,
            arguments: [.object(objectHandle(for: target))]
        )
    }
}
