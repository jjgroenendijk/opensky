// Renderer/engine bridge for the World > Audio panel (M9.1.3). Same shape as
// the other provider extensions: everything runs on the main actor, and with no
// engine, data or renderer the provider degrades to `AudioStatsSnapshot.empty`
// and an empty picker so the panel never crashes.

import AppKit
import simd

/// Where a panel-triggered source lands: straight ahead of the camera, far
/// enough (~10 m) that turning or strafing produces obvious panning.
private enum AudioTriggerPlacement {
    static let offsetUnits: Float = 700
}

extension GameViewController: AudioControlProviding {
    var audioEnabled: Bool {
        get { worldAudio?.isEnabled ?? false }
        set {
            if newValue, worldAudio == nil {
                let engine = WorldAudioEngine()
                worldAudio = engine
                // The renderer's per-frame tick drives the listener pose.
                renderer?.worldAudio = engine
            }
            worldAudio?.isEnabled = newValue
        }
    }

    var audioMasterVolume: Float {
        get { worldAudio?.masterVolume ?? 1 }
        set { worldAudio?.masterVolume = newValue }
    }

    func audioVolume(for category: AudioCategory) -> Float {
        worldAudio?.volume(for: category) ?? 1
    }

    func setAudioVolume(_ volume: Float, for category: AudioCategory) {
        worldAudio?.setVolume(volume, for: category)
    }

    var selectableAudioFileNames: [String] {
        if let cachedAudioFileNames {
            return cachedAudioFileNames
        }
        let names = (audioFileSystem?.archiveEntries() ?? [])
            .map(\.path)
            .filter { $0.lowercased().hasSuffix(".xwm") }
            .sorted()
        cachedAudioFileNames = names
        return names
    }

    func playAudioFile(named name: String) -> String? {
        guard let worldAudio, worldAudio.isRunning else {
            return "audio engine is not running"
        }
        guard let audioFileSystem else {
            return "no game data"
        }
        let camera = renderer?.freeFlyCamera
        let position = (camera?.position ?? .zero)
            + AudioSpace.worldForward(yaw: camera?.yaw ?? 0, pitch: 0)
            * AudioTriggerPlacement.offsetUnits
        do {
            let data = try audioFileSystem.contents(forPath: name)
            // Vanilla `.xwm` is all music, but the trigger exercises the
            // positional-effects path, so it plays under the effects category.
            try worldAudio.playPositional(fileData: data, request: AudioPlayRequest(
                name: name, category: .effects, worldPosition: position
            ))
            return nil
        } catch {
            return String(describing: error)
        }
    }

    func stopAllAudioSources() {
        worldAudio?.stopAllSources()
    }

    var audioStatsSnapshot: AudioStatsSnapshot {
        worldAudio?.statsSnapshot() ?? .empty
    }
}
