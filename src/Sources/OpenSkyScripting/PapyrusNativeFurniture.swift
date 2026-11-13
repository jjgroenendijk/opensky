// `IsFurnitureInUse`, `IsFurnitureMarkerInUse`, and `Game.SetSittingRotation`
// (Creation Kit wiki pages of the same names). The app answers them from the
// furniture seats through `PapyrusFurnitureBridge`.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions.FurnitureNatives {
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
