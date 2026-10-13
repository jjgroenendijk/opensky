// Plays an interface sound by the editor ID of its `SNDR` descriptor, such as
// `UIMenuOK`. The menu movies' `PlaySound` calls and lockpicking use it.

import Foundation
import OpenSkyAudio
import OpenSkyFormatsESM
import OpenSkyRendering
import OpenSkyWorld

final class MenuSoundPlayer {
    /// The movies' `PlayOKSound` call plays this descriptor.
    static let okSound = "UIMenuOK"

    unowned let game: GameViewController
    /// Lowercased SNDR editor ID -> FormID, built on the first sound.
    private var soundIDs: [String: FormID]?

    init(game: GameViewController) {
        self.game = game
    }

    /// Plays at the camera. A missing record stays silent. The file loads off the
    /// main actor, so the first play of a sound may start late.
    func play(editorID: String) {
        guard
            let renderer = game.renderer,
            let engine = renderer.worldAudio, engine.isRunning,
            let assets = game.audio.assets,
            let sounds = (game.worldData as? AudioDataProviding)?.soundStore,
            let formID = soundID(editorID, in: sounds),
            let resolved = try? sounds.resolveAny(formID),
            let path = resolved.filePaths.first
        else { return }
        let request = AudioPlayRequest(
            name: path,
            category: resolved.audioCategory ?? .effects,
            worldPosition: renderer.freeFlyCamera.position
        )
        assets.request(path) { result in
            _ = try? engine.playPositional(asset: result.get(), request: request)
        }
    }

    private func soundID(_ editorID: String, in sounds: SoundRecordStore) -> FormID? {
        if soundIDs == nil {
            var ids: [String: FormID] = [:]
            for descriptor in sounds.descriptors.values {
                if let key = descriptor.editorID?.lowercased(), ids[key] == nil {
                    ids[key] = descriptor.formID
                }
            }
            soundIDs = ids
        }
        return soundIDs?[editorID.lowercased()]
    }
}
