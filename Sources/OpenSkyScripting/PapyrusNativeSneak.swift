// `Actor.StartSneaking()` (<https://ck.uesp.net/wiki/StartSneaking_-_Actor>): the actor
// enters sneak. Only the player has a sneak gait in OpenSky, so another actor does not change.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions {
    static func installSneak(into registry: inout PapyrusNativeRegistry) {
        scriptState("Actor", "StartSneaking", into: &registry) { call, bridge, key in
            guard key == .player else { return .returned(.none) }
            guard let startSneaking = bridge.startPlayerSneaking else {
                return failure(call, "StartSneaking needs the player controller")
            }
            startSneaking()
            return .returned(.none)
        }
    }
}
