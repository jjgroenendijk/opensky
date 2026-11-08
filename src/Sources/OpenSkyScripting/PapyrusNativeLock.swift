// Lock natives of the `ObjectReference` family. They read and write the same
// `ReferenceLockState` the use-key gate checks. See docs/engine/locks.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyInventoryInterface
import OpenSkyScriptingInterface
import OpenSkyWorldState

extension PapyrusNativeFunctions {
    /// The level a `Lock()` gives a reference that has no XLOC. OpenSky's choice:
    /// no source says what the game uses, so the easiest band.
    static let defaultLockLevel: UInt8 = 1

    public static func installLock(into registry: inout PapyrusNativeRegistry) {
        installLockWrites(into: &registry)
        installLockReads(into: &registry)
    }

    /// `Lock(bool abLock = true, bool abAsOwner = false)` and `SetLockLevel(int)`.
    /// `abAsOwner` is ignored: crime does not watch locks yet.
    private static func installLockWrites(into registry: inout PapyrusNativeRegistry) {
        register("Lock", into: &registry) { call, target in
            let locked = boolean(call, at: 0, default: true)
            var state = target.world.lockState(for: target.key) ?? ReferenceLockState(
                isLocked: false, level: defaultLockLevel, key: nil
            )
            state.isLocked = locked
            target.world.write(state.erased, for: target.key)
            return .returned(.none)
        }
        register("SetLockLevel", into: &registry) { call, target in
            guard let level = integer(call, at: 0) else {
                return failure(call, "SetLockLevel needs an int level")
            }
            var state = target.world.lockState(for: target.key)
                ?? ReferenceLockState(isLocked: false, level: defaultLockLevel, key: nil)
            state.level = UInt8(clamping: level)
            target.world.write(state.erased, for: target.key)
            return .returned(.none)
        }
    }

    /// `bool IsLocked()`, `int GetLockLevel()`, and `Key GetKey()`. A reference with no
    /// lock is unlocked, at level 0, with no key.
    private static func installLockReads(into registry: inout PapyrusNativeRegistry) {
        register("IsLocked", into: &registry) { _, target in
            .returned(.boolean(target.world.lockState(for: target.key)?.isLocked ?? false))
        }
        register("GetLockLevel", into: &registry) { _, target in
            let level = target.world.lockState(for: target.key)?.level ?? 0
            return .returned(.integer(Int32(level)))
        }
        register("GetKey", into: &registry) { _, target in
            guard
                let key = target.world.lockState(for: target.key)?.key,
                let keyKey = target.world.referenceKey(forFormID: key),
                let handle = target.world.objectHandle(for: keyKey)
            else { return .returned(.none) }
            return .returned(.object(handle))
        }
    }

    private static func register(
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
