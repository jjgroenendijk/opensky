// How a shout shakes the controller, from the `fShoutRumble*` settings: per word count,
// a duration and a strength for the big and the small motor. Reading the "Frequency"
// settings as motor strength is OpenSky's reading (docs/engine/shouts.md#rumble).

import Foundation
import OpenSkyGameData

nonisolated public struct ShoutRumble: Equatable, Sendable {
    public var bigSeconds: Float
    public var bigStrength: Float
    public var smallSeconds: Float
    public var smallStrength: Float

    public init(bigSeconds: Float, bigStrength: Float, smallSeconds: Float, smallStrength: Float) {
        self.bigSeconds = bigSeconds
        self.bigStrength = bigStrength
        self.smallSeconds = smallSeconds
        self.smallStrength = smallStrength
    }
}

nonisolated public struct ShoutRumbleSettings: Equatable, Sendable {
    /// One entry per word count, from `...V1` to `...V3`.
    public var words = [
        ShoutRumble(bigSeconds: 0.4, bigStrength: 0.1, smallSeconds: 0.4, smallStrength: 0.1),
        ShoutRumble(bigSeconds: 0.8, bigStrength: 0.2, smallSeconds: 0.8, smallStrength: 0.2),
        ShoutRumble(bigSeconds: 1, bigStrength: 0.5, smallSeconds: 1, smallStrength: 0.5)
    ]

    public static let vanilla = Self()

    public init() {}

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        for index in settings.words.indices {
            let suffix = "V\(index + 1)"
            let fields: [(String, WritableKeyPath<ShoutRumble, Float>)] = [
                ("fShoutRumbleBigMotorDuration", \.bigSeconds),
                ("fShoutRumbleBigMotorFrequency", \.bigStrength),
                ("fShoutRumbleSmallMotorDuration", \.smallSeconds),
                ("fShoutRumbleSmallMotorFrequency", \.smallStrength)
            ]
            for (name, keyPath) in fields {
                store.read(name + suffix, into: &settings.words[index], keyPath)
            }
        }
        return settings
    }

    /// The rumble of a shout of `words` words, held to the known word counts.
    public func rumble(words count: Int) -> ShoutRumble? {
        guard !words.isEmpty else { return nil }
        return words[min(max(count, 1), words.count) - 1]
    }
}
