// Position natives of the `ObjectReference` family (issue #172). Satellite of
// `PapyrusNativeObjectReference.swift`, which states the policy these follow.
//
// Only instant placement lives here. `TranslateTo`, `TranslateToRef`,
// `SplineTranslateTo` and the `OnTranslationComplete` event they raise need an
// interpolator the world runtime does not have, so they are deferred to a later
// milestone rather than stubbed into looking successful.

import Foundation

nonisolated extension PapyrusNativeFunctions {
    /// `float GetPositionX()`, `GetPositionY()`, `GetPositionZ()`.
    ///
    /// Read from the resolved `ReferenceState`, so a script that moved the
    /// reference earlier reads back what it wrote, and one that never moved it
    /// reads the plugin's DATA placement.
    static func installPositionReads(into registry: inout PapyrusNativeRegistry) {
        for (axis, name) in ["X", "Y", "Z"].enumerated() {
            registry.register(PapyrusNativeFunction(
                scriptName: "ObjectReference",
                functionName: "GetPosition\(name)"
            ) { call, context in
                guard let target = worldTarget(call, context) else {
                    return needsWorld(call)
                }
                guard let state = target.world.referenceState(for: target.key) else {
                    return needsResidentReference(call)
                }
                return .returned(.float(state.transform.position[axis]))
            })
        }
    }

    /// `SetPosition(float afX, float afY, float afZ)`.
    ///
    /// The write is one `ReferenceTransformOverride`, which carries the whole
    /// placement, so the current rotation and XSCL scale are read back out of
    /// the resolved state and written again unchanged. An axis whose argument
    /// the caller did not pass keeps its current value for the same reason:
    /// the compiler fills Papyrus defaults in, so a short argument list is a
    /// malformed call rather than a request to move to the origin.
    ///
    /// An argument that is present but is not a number, or is not finite, is a
    /// failure — a NaN coordinate would poison every later distance comparison.
    static func installSetPosition(into registry: inout PapyrusNativeRegistry) {
        registry.register(PapyrusNativeFunction(
            scriptName: "ObjectReference",
            functionName: "SetPosition"
        ) { call, context in
            guard let target = worldTarget(call, context) else {
                return needsWorld(call)
            }
            guard let state = target.world.referenceState(for: target.key) else {
                return needsResidentReference(call)
            }
            var position = state.transform.position
            var supplied = false
            for axis in 0 ..< 3 where call.arguments.indices.contains(axis) {
                guard let value = float(call, at: axis), value.isFinite else {
                    return failure(call, "SetPosition needs finite coordinates")
                }
                position[axis] = value
                supplied = true
            }
            guard supplied else {
                return failure(call, "SetPosition needs at least one coordinate")
            }
            target.world.write(
                ReferenceTransformOverride(
                    position: position,
                    rotation: state.transform.rotation,
                    scale: state.transform.scale
                ).erased,
                for: target.key
            )
            return .returned(.none)
        })
    }
}
