// The log of started sounds that `state sounds` reads.

import simd

/// One sound as it started: its file, its category, and where it played.
nonisolated public struct StartedAudioSource: Equatable, Sendable {
    public let id: Int
    public let name: String
    public let category: AudioCategory
    /// Nil for a sound with no place in the world, such as music.
    public let worldPosition: SIMD3<Float>?
    public let loops: Bool
    /// The engine's playback clock when it started.
    public let clockSeconds: Double
}

extension ActiveAudioSource {
    /// The world position, or nil for a sound with no place in the world.
    public var placedPosition: SIMD3<Float>? {
        isPositional || attenuation != nil ? worldPosition : nil
    }
}

extension WorldAudioEngine {
    public static let recentStartLimit = 32

    func recordStart(of source: ActiveAudioSource) {
        recentStarts.append(StartedAudioSource(
            id: source.id, name: source.name, category: source.category,
            worldPosition: source.placedPosition, loops: source.loops,
            clockSeconds: source.startClockSeconds
        ))
        if recentStarts.count > Self.recentStartLimit {
            recentStarts.removeFirst(recentStarts.count - Self.recentStartLimit)
        }
    }
}
