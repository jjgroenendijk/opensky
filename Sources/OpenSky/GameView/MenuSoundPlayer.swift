// Plays an interface sound by the editor ID of its `SNDR` descriptor, such as
// `UIMenuOK`. The menu movies' `PlaySound` calls and lockpicking use it.

import Foundation
import OpenSkyAudio
import OpenSkyFormatsESM
import OpenSkyRendering
import OpenSkyWorld

/// What `MenuSoundPlayer` reads from the session. `GameViewController` conforms.
@MainActor
protocol MenuSoundHost: AnyObject {
    var audio: AudioCoordinator { get }
    var renderer: Renderer? { get }
    var worldData: WorldDataStores? { get }
}

/// What a menu sound needs. Closures, because a reload replaces the renderer and
/// the data.
struct MenuSoundDependencies {
    let audio: AudioCoordinator
    let renderer: () -> Renderer?
    let worldData: () -> WorldDataStores?
}

extension MenuSoundDependencies {
    init(game: any MenuSoundHost) {
        self.init(
            audio: game.audio,
            renderer: { [unowned game] in game.renderer },
            worldData: { [unowned game] in game.worldData }
        )
    }
}

final class MenuSoundPlayer {
    /// The movies' `PlayOKSound` call plays this descriptor.
    static let okSound = "UIMenuOK"

    private let dependencies: MenuSoundDependencies
    /// Lowercased SNDR editor ID -> FormID, built on the first sound.
    private var soundIDs: [String: FormID]?

    init(_ dependencies: MenuSoundDependencies) {
        self.dependencies = dependencies
    }

    /// Plays at the camera. A missing record stays silent. The file loads off the
    /// main actor, so the first play of a sound may start late.
    func play(editorID: String) {
        guard
            let renderer = dependencies.renderer(),
            let engine = renderer.worldAudio, engine.isRunning,
            let assets = dependencies.audio.assets,
            let sounds = dependencies.worldData()?.soundStore,
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
