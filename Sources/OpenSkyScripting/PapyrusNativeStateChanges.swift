// `SendLycanthropyStateChanged` and `SendVampirismStateChanged` tell the actor's scripts,
// its alias scripts included, that a quest changed its state (Creation Kit wiki
// "SendLycanthropyStateChanged - Actor"). The scripts hear the matching event.

import Foundation
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions {
    static func installStateChanges(into registry: inout PapyrusNativeRegistry) {
        let natives = [
            ("SendLycanthropyStateChanged", PapyrusEngineEvents.onLycanthropyStateChanged),
            ("SendVampirismStateChanged", PapyrusEngineEvents.onVampirismStateChanged)
        ]
        for (native, event) in natives {
            scriptState("Actor", native, into: &registry) { call, bridge, key in
                guard let world = bridge.world else { return needsWorld(call) }
                guard !call.arguments.isEmpty else {
                    return failure(call, "\(native) needs the new state")
                }
                let state = boolean(call, at: 0, default: false)
                _ = world.queueActorEvent(event, on: key, arguments: [.boolean(state)])
                return .returned(.none)
            }
        }
    }
}
