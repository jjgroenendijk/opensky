// The `Game` family: `GetPlayer` and `GetForm`. The rest of `Game` lives with the
// system it reaches, such as menus, skills, and levels.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions {
    /// `Actor GetPlayer()`, a global function with no receiver. It returns the
    /// session-stable opaque handle for `ReferenceKey.player`, so `akActionRef ==
    /// Game.GetPlayer()` works. The handle has no `Actor` script, so an `Actor`
    /// method on it is tallied as unimplemented rather than faked.
    public static func installGame(into registry: inout PapyrusNativeRegistry) {
        registry.register(PapyrusNativeFunction(
            scriptName: "Game",
            functionName: "GetPlayer"
        ) { call, context in
            guard
                let world = context.world,
                let handle = world.objectHandle(for: world.playerKey)
            else {
                return failure(call, "GetPlayer needs a world runtime")
            }
            return .returned(.object(handle))
        })
        registry.register(PapyrusNativeFunction(
            scriptName: "Game",
            functionName: "GetForm"
        ) { call, context in
            guard let world = context.world, let formID = integer(call, at: 0) else {
                return failure(call, "GetForm needs a world runtime and an int FormID")
            }
            guard
                formID != 0,
                let key = world.referenceKey(forFormID: FormID(stored: UInt32(bitPattern: formID))),
                let handle = world.objectHandle(for: key)
            else { return .returned(.none) }
            return .returned(.object(handle))
        })
    }
}
