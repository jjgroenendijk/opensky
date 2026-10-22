// `Actor GetPlayersLastRiddenHorse()`
// (<https://ck.uesp.net/wiki/GetPlayersLastRiddenHorse_-_Game>): the same horse the
// `IsPlayersLastRiddenMount` condition reads. `bool Dismount()`
// (<https://ck.uesp.net/wiki/Dismount_-_Actor>): true when a dismount started.

import Foundation
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions {
    static func installMounts(into registry: inout PapyrusNativeRegistry) {
        scriptState("Game", "GetPlayersLastRiddenHorse", into: &registry) { call, bridge, _ in
            guard let lastMount = bridge.playerNatives.playersLastMount else {
                return failure(call, "GetPlayersLastRiddenHorse needs the vehicle runtime")
            }
            let horse = lastMount().flatMap(bridge.objectHandle(for:))
            return .returned(horse.map { .object($0) } ?? .none)
        }
        scriptState("Actor", "Dismount", into: &registry) { call, bridge, actor in
            guard let dismount = bridge.playerNatives.dismount else {
                return failure(call, "Dismount needs the vehicle runtime")
            }
            return .returned(.boolean(dismount(actor)))
        }
    }
}
