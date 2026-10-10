// Runs `RegionSoundScheduler` commands on the engine. Region sounds have no position,
// so they play non-positional. See docs/engine/world-sfx.md#region-sounds.

import OpenSkyAudio
import OpenSkyFormatsCore
import OpenSkyFormatsESM

extension WorldAudioSoundDirector {
    /// The bed the panel readout shows. Reports "none" unless one of this director's
    /// region sources is still alive in the engine.
    public var currentAmbienceDescription: String {
        pruneRetiredAmbienceSources()
        guard !ambienceLoopSources.isEmpty || !ambienceOneShotSources.isEmpty else {
            return "none"
        }
        return desiredBed.entries
            .map(\.sound.description)
            .joined(separator: ", ")
    }

    /// Rolls the region one-shots and follows weather and condition changes.
    public func tickAmbience(deltaTime: Float) {
        guard ambienceEnabled, engine.isRunning else { return }
        let mayPlay = regionSoundGate()
        run(regionSounds.advance(deltaTime: deltaTime, mayPlay: mayPlay))
    }

    /// Single path from wanted state to playing state, shared by the context
    /// change and the panel toggle so the two cannot drift apart.
    func applyAmbienceState() {
        retireAmbience()
        guard ambienceEnabled, engine.isRunning else { return }
        let sounds = desiredBed.entries.compactMap(regionSound)
        run(regionSounds.replace(sounds, mayPlay: regionSoundGate()))
    }

    private func regionSound(_ entry: AmbienceBed.Entry) -> RegionSound? {
        guard let descriptor = try? soundStore?.resolveAny(entry.sound).descriptor else {
            return nil
        }
        let loops = switch descriptor.looping {
        case .some(.loop), .some(.envelopeFast), .some(.envelopeSlow): true
        default: false
        }
        return RegionSound(entry: entry, loops: loops, conditions: descriptor.conditions)
    }

    /// The weather is read once per decision, not once per sound.
    private func regionSoundGate() -> (RegionSound) -> Bool {
        let weather = currentWeather()
        let conditionsPass = soundConditionsPass
        return { $0.entry.plays(in: weather) && conditionsPass($0.conditions) }
    }

    private func run(_ commands: RegionSoundCommands) {
        for sound in commands.stopLoops {
            if let sourceID = ambienceLoopSources.removeValue(forKey: sound) {
                engine.stopSource(id: sourceID)
            }
        }
        for sound in commands.startLoops {
            startRegionSound(sound, loops: true)
        }
        if let sound = commands.oneShot {
            startRegionSound(sound, loops: false)
        }
    }

    /// A loop whose file arrives after the scheduler stopped it does not start.
    private func startRegionSound(_ sound: FormID, loops: Bool) {
        let generation = ambienceGeneration
        playResolved(id: sound, at: nil, kind: "ambience", loops: loops) { [weak self] source in
            guard let self, generation == ambienceGeneration, ambienceEnabled else {
                return false
            }
            guard loops else {
                ambienceOneShotSources.append(source)
                return true
            }
            guard regionSounds.playingLoops.contains(sound), ambienceLoopSources[sound] == nil
            else { return false }
            ambienceLoopSources[sound] = source
            return true
        }
    }

    private func retireAmbience() {
        ambienceGeneration += 1
        _ = regionSounds.stopAll()
        for sourceID in Array(ambienceLoopSources.values) + ambienceOneShotSources {
            engine.stopSource(id: sourceID)
        }
        ambienceLoopSources.removeAll()
        ambienceOneShotSources.removeAll()
    }

    /// Forgets ids the engine already stopped on its own, so the tracked sets
    /// only ever name sources that are actually playing.
    private func pruneRetiredAmbienceSources() {
        let live = Set(engine.sources.map(\.id))
        ambienceLoopSources = ambienceLoopSources.filter { live.contains($0.value) }
        ambienceOneShotSources.removeAll { !live.contains($0) }
    }
}
