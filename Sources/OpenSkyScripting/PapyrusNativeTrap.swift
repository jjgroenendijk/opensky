// Natives the shipped trap and trigger scripts call, from the census over the
// install. Ones the engine can answer are real; physics, shakes, and sounds are
// traced stubs, so a trap script runs on instead of stopping. See docs/engine/traps.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface
import OpenSkyWorldState

extension PapyrusNativeFunctions {
    /// Seconds since the first `GetCurrentRealTime` call, the game's "real time".
    private static let realTimeStart = Date()

    public static func installTrap(into registry: inout PapyrusNativeRegistry) {
        installTrapReads(into: &registry)
        installTrapHit(into: &registry)
        installTrapStubs(into: &registry)
    }

    /// `int GetTriggerObjectCount()`, `Form GetBaseObject()`, `float GetAngleZ()`,
    /// `ObjectReference GetNthLinkedRef(int)`, `bool IsLockBroken()`, and
    /// `float Utility.GetCurrentRealTime()`.
    private static func installTrapReads(into registry: inout PapyrusNativeRegistry) {
        reference("GetTriggerObjectCount", into: &registry) { _, target in
            .returned(.integer(Int32(clamping: target.world.triggerObjectCount(for: target.key))))
        }
        reference("GetBaseObject", into: &registry) { _, target in
            guard
                let base = target.world.placedReference(for: target.key)?.base,
                let key = target.world.referenceKey(forFormID: base),
                let handle = target.world.objectHandle(for: key)
            else { return .returned(.none) }
            return .returned(.object(handle))
        }
        reference("GetAngleZ", into: &registry) { call, target in
            guard let state = target.world.referenceState(for: target.key) else {
                return needsResidentReference(call)
            }
            return .returned(.float(state.transform.rotation.z * 180 / .pi))
        }
        reference("GetNthLinkedRef", into: &registry) { call, target in
            guard let count = integer(call, at: 0) else {
                return failure(call, "GetNthLinkedRef needs an int")
            }
            return .returned(nthLinkedReference(of: target.key, count: count, world: target.world))
        }
        // OpenSky never breaks a lock: a failed pick only costs the pick.
        reference("IsLockBroken", into: &registry) { _, _ in .returned(.boolean(false)) }
        registry.register(PapyrusNativeFunction(
            scriptName: "Utility",
            functionName: "GetCurrentRealTime"
        ) { _, _ in
            .returned(.float(Float(Date().timeIntervalSince(realTimeStart))))
        })
    }

    /// `GetNthLinkedRef(1)` is `GetLinkedRef()`; each step follows the untagged link.
    private static func nthLinkedReference(
        of key: ReferenceKey,
        count: Int32,
        world: any PapyrusWorldBridge
    ) -> PapyrusValue {
        var current = key
        for _ in 0 ..< max(count, 0) {
            guard
                let link = world.placedReference(for: current)?.linkedReference(),
                let next = world.referenceKey(forFormID: link)
            else { return .none }
            current = next
        }
        guard count > 0, let handle = world.objectHandle(for: current) else { return .none }
        return .object(handle)
    }

    /// `ProcessTrapHit(akTrap, afDamage, afPushback, ...)` on the actor hit: the
    /// damage comes off Health. Pushback and stagger need physics and are dropped.
    private static func installTrapHit(into registry: inout PapyrusNativeRegistry) {
        reference("ProcessTrapHit", into: &registry) { call, target in
            guard let damage = float(call, at: 1), damage.isFinite else {
                return failure(call, "ProcessTrapHit needs a finite damage")
            }
            guard let health = ActorValueIdentity.index(named: "Health") else {
                return failure(call, "ProcessTrapHit has no Health actor value")
            }
            guard damage > 0 else { return .returned(.none) }
            guard
                target.world.damageActorValue(
                    at: Int32(health), by: damage, on: target.key
                ) != nil
            else {
                return failure(call, "ProcessTrapHit needs an actor receiver")
            }
            return .returned(.none)
        }
    }

    private static func reference(
        _ functionName: String,
        into registry: inout PapyrusNativeRegistry,
        body: @escaping @MainActor (
            PapyrusNativeCall, (world: any PapyrusWorldBridge, key: ReferenceKey)
        ) -> PapyrusNativeResult
    ) {
        registry.register(PapyrusNativeFunction(
            scriptName: "ObjectReference",
            functionName: functionName
        ) { call, context in
            guard let target = worldTarget(call, context) else {
                return needsWorld(call)
            }
            return body(call, target)
        })
    }
}
