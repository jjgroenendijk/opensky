// `ObjectReference` natives that write the reference's own world state: open state,
// scale, angle, the editor placement, and blocked activation. Signatures are from
// <https://ck.uesp.net/wiki/ObjectReference_Script>.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface
import OpenSkyWorldState

extension PapyrusNativeFunctions {
    /// `GetOpenState` codes: 1 open, 3 closed. OpenSky has no opening or closing phase.
    static let openStateOpen: Int32 = 1
    static let openStateClosed: Int32 = 3

    public static func installReferenceState(into registry: inout PapyrusNativeRegistry) {
        installOpenState(into: &registry)
        installTransformWrites(into: &registry)
        // `BlockActivation(bool abBlocked = true)`: `OnActivate` still runs, but the
        // activation no longer opens or closes the reference.
        scriptState("ObjectReference", "BlockActivation", into: &registry) { call, bridge, key in
            let blocked = boolean(call, at: 0, default: true)
            bridge.updateScriptedState(of: key) {
                $0.setFlag(activationBlockedName, blocked ? true : nil)
            }
            return .returned(.none)
        }
        scriptState("ObjectReference", "IsActivationBlocked", into: &registry) { _, bridge, key in
            .returned(.boolean(bridge.scriptedState(of: key).flag(activationBlockedName) == true))
        }
        // `MoveToMyEditorLocation()`: drops the script's moves, so the plugin placement shows.
        let moveBack = "MoveToMyEditorLocation"
        scriptState("ObjectReference", moveBack, into: &registry) { _, bridge, key in
            bridge.worldState.reset(.transform, for: key)
            bridge.worldState.reset(.relocation, for: key)
            return .returned(.none)
        }
    }

    static let activationBlockedName = "activationBlocked"

    /// `SetOpen(bool abOpen = true)` and `int GetOpenState()`.
    private static func installOpenState(into registry: inout PapyrusNativeRegistry) {
        scriptState("ObjectReference", "SetOpen", into: &registry) { call, bridge, key in
            let current = bridge.worldState.component(ReferenceActivationState.self, for: key)
                ?? bridge.referenceState(for: key)?.activation ?? .untouched
            var next = current
            next.isOpen = boolean(call, at: 0, default: true)
            bridge.write(next.erased, for: key)
            return .returned(.none)
        }
        scriptState("ObjectReference", "GetOpenState", into: &registry) { call, bridge, key in
            guard let state = bridge.referenceState(for: key) else {
                return needsResidentReference(call)
            }
            return .returned(.integer(state.activation.isOpen ? openStateOpen : openStateClosed))
        }
    }

    /// `SetScale(float)` and `SetAngle(float afXAngle, float afYAngle, float afZAngle)`,
    /// with angles in degrees as `GetAngleX` reads them.
    private static func installTransformWrites(into registry: inout PapyrusNativeRegistry) {
        transformWrite("SetScale", into: &registry) { call, transform in
            guard let scale = float(call, at: 0), scale.isFinite, scale > 0 else { return nil }
            var scaled = transform
            scaled.scale = scale
            return scaled
        }
        transformWrite("SetAngle", into: &registry) { call, transform in
            var rotation = transform.rotation
            for axis in 0 ..< 3 {
                guard let degrees = float(call, at: axis), degrees.isFinite else { return nil }
                rotation[axis] = degrees * .pi / 180
            }
            return ReferenceTransformOverride(
                position: transform.position, rotation: rotation, scale: transform.scale
            )
        }
    }

    /// Registers a write of the whole transform. `change` answers nil for bad arguments.
    private static func transformWrite(
        _ name: String,
        into registry: inout PapyrusNativeRegistry,
        change: @escaping @MainActor (
            PapyrusNativeCall, ReferenceTransformOverride
        ) -> ReferenceTransformOverride?
    ) {
        scriptState("ObjectReference", name, into: &registry) { call, bridge, key in
            guard let state = bridge.referenceState(for: key) else {
                return needsResidentReference(call)
            }
            let transform = ReferenceTransformOverride(
                position: state.transform.position,
                rotation: state.transform.rotation,
                scale: state.transform.scale
            )
            guard let next = change(call, transform) else {
                return failure(call, "\(name) needs finite numbers")
            }
            bridge.write(next.erased, for: key)
            return .returned(.none)
        }
    }
}
