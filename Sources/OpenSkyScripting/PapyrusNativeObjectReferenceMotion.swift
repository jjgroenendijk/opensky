// Position natives of the `ObjectReference` family: instant placement only.
// `TranslateTo` and the other motion natives need an interpolator, so they stay
// unregistered rather than faked (docs/engine/papyrus-activation.md).

import Foundation
import OpenSkyScriptingInterface
import OpenSkyWorldState

extension PapyrusNativeFunctions {
    /// `float GetPositionX()`, `GetPositionY()`, `GetPositionZ()`.
    ///
    /// Read from the resolved `ReferenceState`, so a script that moved the
    /// reference earlier reads back what it wrote, and one that never moved it
    /// reads the plugin's DATA placement.
    public static func installPositionReads(into registry: inout PapyrusNativeRegistry) {
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

    /// `SetPosition(float afX, float afY, float afZ)`. The write is one whole
    /// `ReferenceTransformOverride`, so rotation, scale, and any axis not passed
    /// keep their current values. A non-numeric or non-finite argument fails,
    /// because a NaN coordinate would break every later distance check.
    public static func installSetPosition(into registry: inout PapyrusNativeRegistry) {
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
