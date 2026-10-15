// The scripted music stack: `MusicType.Add` and `Remove` over the session's music
// director. Keys convert through the script load order.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyWorld

extension ScriptWorldAdapter: PapyrusMusicControlling {
    func addMusic(_ music: ReferenceKey) -> Bool {
        guard let director = game.audio.musicDirector, let id = musicFormID(music) else {
            return false
        }
        return director.addScriptedMusic(id) == nil
    }

    func removeMusic(_ music: ReferenceKey) {
        guard let id = musicFormID(music) else { return }
        game.audio.musicDirector?.removeScriptedMusic(id)
    }

    private func musicFormID(_ key: ReferenceKey) -> FormID? {
        guard case let .plugin(plugin, objectID) = key else { return nil }
        return game.scripts.bridge?.formIDResolver?
            .localFormID(of: ResolvedFormID(plugin: plugin, objectID: objectID))
    }
}
