// Papyrus `Sound.Play`, `PlayAndWait`, `StopInstance`, and `SetInstanceVolume` over the
// engine's sources (<https://ck.uesp.net/wiki/Sound_Script>).

import OpenSkyAudio
import OpenSkyFormatsESM
import simd

extension WorldAudioSoundDirector {
    /// Starts `formID` at `position` and returns its instance ID; 0 when it cannot play.
    /// A Papyrus `Sound` is a `SOUN`, which names its `SNDR`; a bare `SNDR` plays too.
    /// A `waitToken` is answered through `retireScriptSounds` when the sound ends.
    public func playScriptSound(
        formID: FormID, at position: SIMD3<Float>, waitToken: UInt64? = nil
    ) -> Int32 {
        guard
            engine.isRunning,
            let descriptor = try? soundStore?.resolveAny(formID).descriptor
        else { return 0 }
        let id = scriptSounds.begin(waitToken: waitToken)
        playResolved(
            id: formID, at: position, kind: "Script",
            loops: Self.loops(descriptor),
            adopt: { [weak self] source in
                guard let self else { return false }
                let adoption = scriptSounds.adopt(id, source: source)
                if let volume = adoption.volume {
                    engine.fadeSource(id: source, to: volume, overSeconds: 0)
                }
                return adoption.keeps
            },
            failed: { [weak self] in self?.failedScriptSounds.insert(id) }
        )
        return id
    }

    public func stopScriptSound(_ id: Int32) {
        if let source = scriptSounds.stop(id) {
            engine.stopSource(id: source)
        }
    }

    public func setScriptSoundVolume(_ id: Int32, _ volume: Float) {
        guard let source = scriptSounds.setVolume(id, volume) else { return }
        engine.fadeSource(id: source, to: scriptSounds.volume(of: id) ?? 1, overSeconds: 0)
    }

    /// Forgets ended script sounds. Returns each `PlayAndWait` answer by its token.
    public func retireScriptSounds() -> [UInt64: Bool] {
        let failed = failedScriptSounds
        failedScriptSounds = []
        return scriptSounds.retire(playing: Set(engine.sources.map(\.id)), failed: failed)
    }
}
