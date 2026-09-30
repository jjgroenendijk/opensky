// The `Game` family. Only `GetPlayer` is installed: the rest of `Game` needs
// session systems that do not exist yet.

import Foundation
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
    }
}
