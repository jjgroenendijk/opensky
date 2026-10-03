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

extension PapyrusNativeFunctions {
    public static func installObjectReference(into registry: inout PapyrusNativeRegistry) {
        installEnableState(into: &registry)
        installDeletion(into: &registry)
        installPositionReads(into: &registry)
        installSetPosition(into: &registry)
        installActivate(into: &registry)
        installLinkedReference(into: &registry)
    }

    /// The world façade plus the world identity of `self`, or nil when either
    /// is missing. Every world-touching native starts with this.
    public static func worldTarget(
        _ call: PapyrusNativeCall,
        _ context: PapyrusNativeContext
    ) -> (world: any PapyrusWorldBridge, key: ReferenceKey)? {
        guard
            let world = context.world,
            let receiver = call.receiver,
            let key = world.referenceKey(for: receiver)
        else { return nil }
        return (world, key)
    }

    /// The single failure a world native returns when it has no world to talk
    /// to, or no world identity for its receiver.
    public static func needsWorld(_ call: PapyrusNativeCall) -> PapyrusNativeResult {
        failure(
            call,
            "\(call.functionName) needs a world runtime and a reference receiver"
        )
    }

    /// The failure for a reference whose plugin baseline no resident cell can
    /// supply, which is what stops a read from inventing a position.
    public static func needsResidentReference(
        _ call: PapyrusNativeCall
    ) -> PapyrusNativeResult {
        failure(
            call,
            "\(call.functionName) needs a reference a resident cell knows"
        )
    }

    /// `Enable(bool abFadeIn = false)`, `Disable(bool abFadeOut = false)`, and
    /// `bool IsEnabled()`. The fade argument is ignored: there is no fade, and the
    /// stored state is the same either way.
    private static func installEnableState(
        into registry: inout PapyrusNativeRegistry
    ) {
        for (functionName, isEnabled) in [("Enable", true), ("Disable", false)] {
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

    /// `Delete()`. Writes a `ReferenceDeletionState` delta at once, which the save
    /// keeps. It differs from the record header's deleted flag. OpenSky has no
    /// reference counting, so it does not wait until nothing holds the reference.
    private static func installDeletion(
        into registry: inout PapyrusNativeRegistry
    ) {
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
    }
}
