// Sounds a clip annotation names by `SNDR` editor ID (`SoundPlay.<editor ID>`). A looping
// descriptor keeps playing until the same source sends `SoundStop` for it.
// See docs/engine/animation-events.md.

import Foundation
import OpenSkyAudio
import OpenSkyFormatsESM
import simd

/// One looping animation sound: who started it, and which descriptor.
struct AnimationSoundKey: Hashable {
    let source: ReferenceKey
    /// Lowercased, because annotation and record case differ.
    let editorID: String
}

extension WorldAudioSoundDirector {
    /// Plays the descriptor at `position`. False when no `SNDR` has the editor ID.
    @discardableResult
    public func playAnimationSound(
        editorID: String, source: ReferenceKey, at position: SIMD3<Float>
    ) -> Bool {
        guard let descriptor = descriptor(editorID: editorID) else {
            lastSFXError = "no SNDR \(editorID)"
            return false
        }
        guard sfxEnabled, engine.isRunning else { return true }
        guard Self.loops(descriptor) else {
            playResolved(id: descriptor.formID, at: position, kind: "animation sound")
            return true
        }
        let key = AnimationSoundKey(source: source, editorID: editorID.lowercased())
        stopAnimationLoop(key)
        nextLoopToken += 1
        let token = nextLoopToken
        animationLoopTokens[key] = token
        playResolved(
            id: descriptor.formID, at: position, kind: "animation loop", loops: true
        ) { [weak self] sourceID in
            guard let self, animationLoopTokens[key] == token else { return false }
            animationLoopSourceIDs[key] = sourceID
            return true
        }
        return true
    }

    /// Ends the loop of `editorID` that `source` started. A loop still loading never starts.
    public func stopAnimationSound(editorID: String, source: ReferenceKey) {
        stopAnimationLoop(AnimationSoundKey(source: source, editorID: editorID.lowercased()))
    }

    /// How many animation loops play, for the readout and tests.
    public var animationLoopCount: Int {
        animationLoopSourceIDs.count
    }

    private func stopAnimationLoop(_ key: AnimationSoundKey) {
        animationLoopTokens[key] = nil
        if let sourceID = animationLoopSourceIDs.removeValue(forKey: key) {
            engine.stopSource(id: sourceID)
        }
    }

    private func descriptor(editorID: String) -> SoundDescriptor? {
        guard let soundStore else { return nil }
        if soundIDsByEditorID == nil {
            var ids: [String: FormID] = [:]
            for descriptor in soundStore.descriptors.values {
                if let key = descriptor.editorID?.lowercased(), ids[key] == nil {
                    ids[key] = descriptor.formID
                }
            }
            soundIDsByEditorID = ids
        }
        return soundIDsByEditorID?[editorID.lowercased()].flatMap(soundStore.descriptor)
    }

    static func loops(_ descriptor: SoundDescriptor) -> Bool {
        switch descriptor.looping {
        case .some(.loop), .some(.envelopeFast), .some(.envelopeSlow): true
        default: false
        }
    }
}
