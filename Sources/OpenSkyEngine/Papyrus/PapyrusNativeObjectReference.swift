// Core `ObjectReference` natives (issue #172): the family that lets a script
// visibly change the world. Every write goes through `PapyrusWorldAccess` into
// `WorldStateStore`, so the journal, the dirty counts, the cell rebuild and the
// save all see it.
//
// Policy shared by the whole family, stated once here rather than repeated in
// each satellite file:
//
// * Every one of these natives needs `PapyrusNativeContext.world`. A headless
//   runtime leaves it nil and the native then fails with a reason instead of
//   pretending a write happened. `PapyrusInterpreter` turns a failure into the
//   call's declared default and keeps running, so a headless script still
//   completes — it just changes nothing.
// * `self` arrives as `PapyrusNativeCall.receiver` and becomes a
//   `ReferenceKey` through `PapyrusWorldAccess.referenceKey(for:)`. A handle no
//   world runtime handed out has no world identity and fails the same way.
// * A write never requires the reference to be resident: a script may disable
//   a reference in a cell nobody has streamed, and `WorldStateStore` keeps the
//   delta until a cell build asks for it. A read that needs the plugin
//   baseline — `IsEnabled`, the position getters, and `SetPosition`, which
//   preserves the parts of the transform it is not given — does require it,
//   because there is nothing honest to answer with otherwise.
//
// Signatures follow the Creation Kit wiki's ObjectReference script reference.
// Deliberately absent: `TranslateTo` and every other spline or interpolated
// motion, which is a later milestone; only instant `SetPosition` exists in M11.
// `Enable`/`Disable` act on the receiver alone, because XESP enable-parent
// chains are not decoded — a documented gap for M18+.

import Foundation

nonisolated extension PapyrusNativeFunctions {
    static func installObjectReference(into registry: inout PapyrusNativeRegistry) {
        installEnableState(into: &registry)
        installDeletion(into: &registry)
        installPositionReads(into: &registry)
        installSetPosition(into: &registry)
        installActivate(into: &registry)
        installLinkedReference(into: &registry)
    }

    /// The world façade plus the world identity of `self`, or nil when either
    /// is missing. Every world-touching native starts with this.
    static func worldTarget(
        _ call: PapyrusNativeCall,
        _ context: PapyrusNativeContext
    ) -> (world: PapyrusWorldAccess, key: ReferenceKey)? {
        guard
            let world = context.world,
            let receiver = call.receiver,
            let key = world.referenceKey(for: receiver)
        else { return nil }
        return (world, key)
    }

    /// The single failure a world native returns when it has no world to talk
    /// to, or no world identity for its receiver.
    static func needsWorld(_ call: PapyrusNativeCall) -> PapyrusNativeResult {
        failure(
            call,
            "\(call.functionName) needs a world runtime and a reference receiver"
        )
    }

    /// The failure for a reference whose plugin baseline no resident cell can
    /// supply, which is what stops a read from inventing a position.
    static func needsResidentReference(
        _ call: PapyrusNativeCall
    ) -> PapyrusNativeResult {
        failure(
            call,
            "\(call.functionName) needs a reference a resident cell knows"
        )
    }

    /// `Enable(bool abFadeIn = false)`, `Disable(bool abFadeOut = false)`, and
    /// `bool IsEnabled()`.
    ///
    /// The fade argument is accepted and ignored: M11 has no fade-in or
    /// fade-out, so a reference appears and disappears on the next cell
    /// rebuild. That is a stated simplification, not a silent one — the state
    /// written is identical either way, so no script logic depends on it.
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
        registry.register(PapyrusNativeFunction(
            scriptName: "ObjectReference",
            functionName: "IsEnabled"
        ) { call, context in
            guard let target = worldTarget(call, context) else {
                return needsWorld(call)
            }
            guard let state = target.world.referenceState(for: target.key) else {
                return needsResidentReference(call)
            }
            return .returned(.boolean(state.enableState.isEnabled))
        })
    }

    /// `Delete()`.
    ///
    /// This is runtime deletion — a `ReferenceDeletionState` delta that drops
    /// the reference from the drawn set and persists in the save — and is a
    /// different thing from the record header's deleted flag, which means the
    /// plugin removed the record at load time. The Creation Kit's own
    /// documentation warns that `Delete` only takes effect on a reference that
    /// nothing else holds; OpenSky has no reference counting yet, so the delta
    /// is written unconditionally.
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
