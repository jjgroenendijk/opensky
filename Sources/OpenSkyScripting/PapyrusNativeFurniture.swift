// `IsFurnitureInUse`, `IsFurnitureMarkerInUse`, and `Game.SetSittingRotation`
// (Creation Kit wiki pages of the same names). The app answers them from the
// furniture seats through `PapyrusFurnitureBridge`.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface
import OpenSkyWorldInterface

/// What the furniture natives reach. The app answers it.
@MainActor
public protocol PapyrusFurnitureBridge: AnyObject {
    /// Whether an actor uses `marker` of the furniture, or any marker when nil. A
    /// reserved marker counts too unless `ignoringReserved`.
    func isFurnitureInUse(_ furniture: ReferenceKey, marker: Int?, ignoringReserved: Bool) -> Bool
    /// Turns the seated player's first-person view by `degrees` from the seat's
    /// facing; negative looks left.
    func setSittingRotation(degrees: Float)
}

extension PapyrusNativeFunctions {
    static func installFurniture(into registry: inout PapyrusNativeRegistry) {
        // A call on an `Actor` variable looks the native up under `Actor`.
        for script in ["ObjectReference", "Actor"] {
            registry.register(PapyrusNativeFunction(
                scriptName: script, functionName: "IsFurnitureInUse"
            ) { call, context in
                inUse(call, context, marker: nil, ignoreIndex: 0)
            })
            registry.register(PapyrusNativeFunction(
                scriptName: script, functionName: "IsFurnitureMarkerInUse"
            ) { call, context in
                guard let marker = integer(call, at: 0) else {
                    return failure(call, "IsFurnitureMarkerInUse needs a marker index")
                }
                return inUse(call, context, marker: Int(marker), ignoreIndex: 1)
            })
        }
        registry.register(PapyrusNativeFunction(
            scriptName: "Game", functionName: "SetSittingRotation"
        ) { call, context in
            guard let furniture = (context.world as? PapyrusWorldStateBridge)?.furniture else {
                return needsWorld(call)
            }
            guard let degrees = float(call, at: 0) else {
                return failure(call, "SetSittingRotation needs an angle")
            }
            furniture.setSittingRotation(degrees: degrees)
            return .returned(.none)
        })
    }

    private static func inUse(
        _ call: PapyrusNativeCall, _ context: PapyrusNativeContext, marker: Int?, ignoreIndex: Int
    ) -> PapyrusNativeResult {
        guard
            let world = context.world as? PapyrusWorldStateBridge, let furniture = world.furniture,
            let receiver = call.receiver, let key = world.referenceKey(for: receiver)
        else { return needsWorld(call) }
        let ignoringReserved = boolean(call, at: ignoreIndex, default: false)
        return .returned(.boolean(
            furniture.isFurnitureInUse(key, marker: marker, ignoringReserved: ignoringReserved)
        ))
    }
}
