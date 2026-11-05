// Starts, moves, and stops the breath and movement loops of the actors near the listener.
// The plan is pure (`ActorLoopPlan`); this file applies it. See docs/engine/actor-sounds.md.

import OpenSkyAudio
import OpenSkyFormatsESM
import simd

extension WorldAudioSoundDirector {
    /// Brings the playing actor loops in line with `sources`. A loop already playing
    /// follows its actor; one no longer wanted stops.
    public func updateActorLoops(_ sources: [ActorSoundSource], listener: SIMD3<Float>) {
        let wanted = sfxEnabled && engine.isRunning
            ? ActorLoopPlan.wanted(sources, listener: listener) : [:]
        for loop in actorLoops.keys where wanted[loop] == nil {
            stopSound(formID: loop.sound, source: loop.actor)
            actorLoops[loop] = nil
        }
        for (loop, position) in wanted {
            if actorLoops[loop] == nil {
                guard playSound(formID: loop.sound, source: loop.actor, at: position) else {
                    continue
                }
            } else {
                moveSound(formID: loop.sound, source: loop.actor, to: position)
            }
            actorLoops[loop] = position
        }
    }

    /// The editor IDs of the loops `actor` plays, for the readout.
    public func actorLoopNames(of actor: ReferenceKey) -> [String] {
        actorLoops.keys.filter { $0.actor == actor }
            .map { soundStore?.descriptor($0.sound)?.editorID ?? "\($0.sound)" }
            .sorted()
    }

    /// Moves the loop of `formID` that `source` started, if it plays.
    func moveSound(formID: FormID, source: ReferenceKey, to position: SIMD3<Float>) {
        guard let editorID = soundStore?.descriptor(formID)?.editorID else { return }
        let key = AnimationSoundKey(source: source, editorID: editorID.lowercased())
        if let sourceID = animationLoopSourceIDs[key] {
            engine.moveSource(id: sourceID, to: position)
        }
    }
}
