// Published Equatable snapshot of the world audio graph — the only value that
// crosses from the engine to the audio readout.

import AVFAudio

extension WorldAudioEngine {
    public func statsSnapshot() -> AudioStatsSnapshot {
        AudioStatsSnapshot(
            enabled: isEnabled,
            engineRunning: isRunning,
            sources: sources.map { source in
                AudioSourceStatsSnapshot(
                    name: source.name,
                    categoryName: source.category.displayName,
                    isPositional: source.isPositional,
                    distanceMeters: source.isPositional ? AudioSpace.distanceMeters(
                        fromWorld: listenerWorldPosition,
                        toWorld: source.worldPosition
                    ) : 0,
                    fadeGain: source.fadeGain,
                    isFading: source.activeFade != nil,
                    effectiveGain: effectiveGain(of: source),
                    positionSeconds: playbackPosition(ofSource: source.id)
                )
            },
            sourceCap: Self.maxConcurrentSources,
            reverb: reverb
        )
    }
}
