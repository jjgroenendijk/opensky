// `MusicType.Add()` and `MusicType.Remove()` (<https://ck.uesp.net/wiki/MusicType_Script>).
// The receiver is the `MUSC` form. The music director keeps the scripted stack.

import Foundation
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions {
    static func installMusic(into registry: inout PapyrusNativeRegistry) {
        scriptState("MusicType", "Add", into: &registry) { call, bridge, key in
            guard let music = bridge.music else {
                return failure(call, "Add needs the music director")
            }
            guard music.addMusic(key) else {
                return failure(call, "Add needs a music type with a playable track")
            }
            return .returned(.none)
        }
        scriptState("MusicType", "Remove", into: &registry) { call, bridge, key in
            guard let music = bridge.music else {
                return failure(call, "Remove needs the music director")
            }
            music.removeMusic(key)
            return .returned(.none)
        }
    }
}
