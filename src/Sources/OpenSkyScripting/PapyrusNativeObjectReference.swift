// Core `ObjectReference` natives, the family that visibly changes the world.
// Each write goes through `PapyrusWorldBridge` into `WorldStateStore`, so the
// journal, the cell rebuild, and the save see it. A write works on a reference
// that is not resident. A read that needs the plugin baseline requires it.
//
// Documented in docs/engine/papyrus-activation.md, with the gaps against the game.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface
import OpenSkyWorldState

extension PapyrusNativeFunctions.ObjectReferenceNatives {
    public static func installObjectReference(into registry: inout PapyrusNativeRegistry) {
        installEnableState(into: &registry)
        installDeletion(into: &registry)
        PapyrusNativeFunctions.ObjectReferenceMotionNatives.installPositionReads(into: &registry)
        PapyrusNativeFunctions.ObjectReferenceMotionNatives.installSetPosition(into: &registry)
        PapyrusNativeFunctions.ObjectReferenceLinksNatives.installActivate(into: &registry)
        PapyrusNativeFunctions.ObjectReferenceLinksNatives.installLinkedReference(into: &registry)
    }

    /// `Enable(bool abFadeIn = false)`, `Disable(bool abFadeOut = false)`, their
    /// `NoWait` forms, and `bool IsEnabled()`. There is no fade, so the fade argument
    /// is ignored and a call never waits; the stored state is the same either way.
    private static func installEnableState(into registry: inout PapyrusNativeRegistry) {
        let writes = [
            ("Enable", true), ("EnableNoWait", true), ("Disable", false), ("DisableNoWait", false)
        ]
        for (functionName, isEnabled) in writes {
            registry.register(PapyrusNativeFunction(
                scriptName: "ObjectReference",
                functionName: functionName
            ) { call, context in
                guard let target = worldTarget(call, context) else {
                    return needsWorld(call)
                }
                target.world.write(
                    ReferenceEnableState(isEnabled: isEnabled).erased,
                    for: target.key
                )
                return .returned(.none)
            })
        }
        for (name, enabledAnswer) in [("IsEnabled", true), ("IsDisabled", false)] {
            registry.register(PapyrusNativeFunction(
                scriptName: "ObjectReference",
                functionName: name
            ) { call, context in
                guard let target = worldTarget(call, context) else {
                    return needsWorld(call)
                }
                guard let state = target.world.referenceState(for: target.key) else {
                    return needsResidentReference(call)
                }
                return .returned(.boolean(state.enableState.isEnabled == enabledAnswer))
            })
        }
    }

    /// `Delete()` and `bool IsDeleted()`. Writes a `ReferenceDeletionState` delta at
    /// once, which the save keeps. It differs from the record header's deleted flag.
    /// OpenSky has no reference counting, so it does not wait until nothing holds it.
    private static func installDeletion(into registry: inout PapyrusNativeRegistry) {
        registry.register(PapyrusNativeFunction(
            scriptName: "ObjectReference",
            functionName: "Delete"
        ) { call, context in
            guard let target = worldTarget(call, context) else {
                return needsWorld(call)
            }
            target.world.write(ReferenceDeletionState.deleted.erased, for: target.key)
            return .returned(.none)
        })
        registry.register(PapyrusNativeFunction(
            scriptName: "ObjectReference",
            functionName: "IsDeleted"
        ) { call, context in
            guard let target = worldTarget(call, context) else {
                return needsWorld(call)
            }
            guard let state = target.world.referenceState(for: target.key) else {
                return needsResidentReference(call)
            }
            return .returned(.boolean(state.deletion.isDeleted))
        })
    }
}
