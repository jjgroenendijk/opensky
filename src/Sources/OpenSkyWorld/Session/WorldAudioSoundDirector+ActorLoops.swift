// Starts, moves, and stops the conscious loops of the actors near the listener, and plays
// the sound type an actor's `enum_` event asks for. The plan is pure (`ActorLoopPlan`);
// this file applies it. See docs/engine/actor-sounds.md.

public import OpenSkyAudio
public import OpenSkyFormatsESM
import simd

extension WorldAudioSoundDirector {
    /// Brings the playing actor loops in line with `sources`. A loop already playing
    /// follows its actor; one no longer wanted stops.
    public func updateActorLoops(_ sources: [ActorSoundSource], listener: SIMD3<Float>) {
        ActorLoopUpdate(director: self).updateActorLoops(sources, listener: listener)
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

    /// Plays the sound that one event of the sound type `type` picks for `actor`. False
    /// when the actor has no such sound or no roll passed.
    public func playSoundType(
        _ type: UInt32, actor: ReferenceKey, at position: SIMD3<Float>
    ) -> Bool {
        guard
            let kind = ActorSoundKind(rawValue: type),
            let sounds = actorSoundTypes[actor],
            let sound = sounds.pick(kind, roll: { regionSounds.pick(count: 100) })
        else { return false }
        return playSound(formID: sound, source: actor, at: position)
    }

    /// Ends every animation loop `source` started, except the conscious loops the loop
    /// update keeps.
    public func endAnimationSounds(source: ReferenceKey) {
        let kept = Set(actorLoops.keys.filter { $0.actor == source }.compactMap {
            soundStore?.descriptor($0.sound)?.editorID?.lowercased()
        })
        let started = Set(animationLoopTokens.keys).union(animationLoopSourceIDs.keys)
        for key in started where key.source == source && !kept.contains(key.editorID) {
            stopAnimationSound(editorID: key.editorID, source: source)
        }
    }
}

extension WorldAudioSoundDirector.ActorLoopUpdate {
    func updateActorLoops(_ sources: [ActorSoundSource], listener: SIMD3<Float>) {
        director.actorSoundTypes = Dictionary(
            sources.map { ($0.key, $0.sounds) }, uniquingKeysWith: { first, _ in first }
        )
        let wanted = director.sfxEnabled && director.engine.isRunning
            ? ActorLoopPlan.wanted(sources, listener: listener) : [:]
        for loop in director.actorLoops.keys where wanted[loop] == nil {
            director.stopSound(formID: loop.sound, source: loop.actor)
            director.actorLoops[loop] = nil
        }
        for (loop, position) in wanted {
            if director.actorLoops[loop] == nil {
                guard director.playSound(formID: loop.sound, source: loop.actor, at: position)
                else {
                    continue
                }
            } else {
                director.moveSound(formID: loop.sound, source: loop.actor, to: position)
            }
            director.actorLoops[loop] = position
        }
    }
}
