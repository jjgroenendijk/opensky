// Trap natives that move or fire things: `SetMotionType`, `Reset`, and `Weapon.Fire`.
// The app answers through `PapyrusTrapWorldBridge`. See docs/engine/traps.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface
import OpenSkyWorldState

extension PapyrusNativeFunctions {
    static func installTrapMotion(into registry: inout PapyrusNativeRegistry) {
        // `SetMotionType(int aiMotionType, bool abAllowActivate = true)`. The second
        // argument is not read: a body made dynamic starts to fall at once.
        trapWorldReference("SetMotionType", into: &registry) { call, target in
            guard
                let value = integer(call, at: 0),
                let motionType = ReferenceMotionType(papyrusValue: value)
            else { return failure(call, "SetMotionType needs a motion type from 1 to 6") }
            _ = target.trapWorld.setMotionType(motionType, of: target.key)
            return .returned(.none)
        }
        // `Reset(ObjectReference akTarget = None)`. An actor is not reset yet.
        trapWorldReference("Reset", into: &registry) { call, target in
            let destination = objectArgument(call, at: 0)
                .flatMap { target.world.referenceKey(for: $0) }
            guard target.trapWorld.resetReference(target.key, to: destination) else {
                return .deviated(.none, .stubbed)
            }
            return .returned(.none)
        }
        installWeaponFire(into: &registry)
    }

    /// `Weapon.Fire(ObjectReference akSource, Ammo akAmmo = None)`: the receiver is the
    /// weapon form, and the shot leaves `akSource` along its facing.
    private static func installWeaponFire(into registry: inout PapyrusNativeRegistry) {
        registry.register(PapyrusNativeFunction(
            scriptName: "Weapon",
            functionName: "Fire"
        ) { call, context in
            guard
                let world = context.world as? PapyrusWorldStateBridge,
                let receiver = call.receiver, let weapon = world.referenceKey(for: receiver)
            else { return needsWorld(call) }
            guard
                let handle = objectArgument(call, at: 0),
                let source = world.referenceKey(for: handle)
            else { return failure(call, "Fire needs a source reference") }
            guard let trapWorld = world.trapWorld else {
                context.log.append("Stubbed \(call.qualifiedName)")
                return .deviated(.none, .stubbed)
            }
            let ammunition = objectArgument(call, at: 1).flatMap { world.referenceKey(for: $0) }
            _ = trapWorld.fireWeapon(weapon, from: source, ammunition: ammunition)
            return .returned(.none)
        })
    }
}
