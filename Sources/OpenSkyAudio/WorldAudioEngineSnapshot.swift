// Published Equatable snapshot of the world audio graph — the only value that
// crosses from the engine to the World > Audio readout (2 Hz ticker).

import AVFAudio

extension WorldAudioEngine {
    /// Output device format line for the panel readout.
    public var outputFormatDescription: String {
        let format = engine.outputNode.outputFormat(forBus: 0)
        return "\(Int(format.sampleRate)) Hz, \(format.channelCount) ch"
    }

    public func statsSnapshot() -> AudioStatsSnapshot {
        let output: String = if let unavailableReason {
            "failed: \(unavailableReason)"
        } else if isRunning {
            outputFormatDescription
        } else {
            "stopped"
        }
        return AudioStatsSnapshot(
            enabled: isEnabled,
            engineRunning: isRunning,
            outputDescription: output,
            sources: sources.map { source in
                AudioSourceStatsSnapshot(
                    name: source.name,
                    categoryName: source.category.displayName,
                    isPositional: source.isPositional,
                    worldPosition: source.worldPosition,
                    distanceMeters: source.isPositional ? AudioSpace.distanceMeters(
                        fromWorld: listenerWorldPosition,
                        toWorld: source.worldPosition
                    ) : 0,
                    fadeGain: source.fadeGain,
                    isFading: source.activeFade != nil,
                    effectiveGain: effectiveGain(of: source),
                    positionSeconds: playbackPosition(ofSource: source.id),
                    outputModel: source.outputModelName,
                    distanceGain: source.distanceGain
                )
            },
            sourceCap: Self.maxConcurrentSources,
            reverb: reverb
        )
    }
}
