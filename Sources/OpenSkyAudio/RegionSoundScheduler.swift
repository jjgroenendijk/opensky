// Region sounds: a looping sound plays as a steady bed while it may play, and at a
// random interval the one-shots roll their chance in order and the first hit plays.
// See docs/engine/world-sfx.md#region-sounds.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

/// One region sound with what its SNDR says about it.
nonisolated public struct RegionSound: Equatable, Sendable {
    public let entry: AmbienceBed.Entry
    /// `SNDR` `LNAM` asks for a loop or an envelope.
    public let loops: Bool
    /// The `SNDR` CTDA conditions, run on the player.
    public let conditions: [Condition]

    public init(entry: AmbienceBed.Entry, loops: Bool, conditions: [Condition] = []) {
        self.entry = entry
        self.loops = loops
        self.conditions = conditions
    }
}

/// What the director does next, by sound FormID.
nonisolated public struct RegionSoundCommands: Equatable, Sendable {
    public var stopLoops: [FormID] = []
    public var startLoops: [FormID] = []
    public var oneShot: FormID?

    public init() {}
}

nonisolated public struct RegionSoundScheduler: Equatable, Sendable {
    /// Seconds between two rolls. [WARNING] Provisional: no open source gives Skyrim's
    /// interval, so this is Morrowind's, from OpenMW's fallback settings.
    public static let rollInterval: ClosedRange<Float> = 1 ... 5

    public private(set) var sounds: [RegionSound] = []
    /// The loops asked to play, in bed order.
    public private(set) var playingLoops: [FormID] = []
    private var random: SplitMix64
    private var untilRoll: Float = 0

    public init(seed: UInt64 = SplitMix64.increment) {
        random = SplitMix64(seed: seed)
        untilRoll = nextInterval()
    }

    /// A new bed stops every loop of the old one, then starts the loops that may play.
    public mutating func replace(
        _ sounds: [RegionSound],
        mayPlay: (RegionSound) -> Bool
    ) -> RegionSoundCommands {
        var commands = RegionSoundCommands()
        commands.stopLoops = playingLoops
        playingLoops = []
        self.sounds = sounds
        commands.startLoops = refreshLoops(mayPlay: mayPlay).startLoops
        return commands
    }

    /// Stops every loop, as turning ambience off does. The bed stays wanted.
    public mutating func stopAll() -> [FormID] {
        defer { playingLoops = [] }
        return playingLoops
    }

    /// On a roll, checks the loops again and rolls the one-shots that may play.
    public mutating func advance(
        deltaTime: Float,
        mayPlay: (RegionSound) -> Bool
    ) -> RegionSoundCommands {
        untilRoll -= max(0, deltaTime)
        guard untilRoll <= 0 else { return RegionSoundCommands() }
        untilRoll = nextInterval()
        var commands = refreshLoops(mayPlay: mayPlay)
        let candidates = sounds.filter { !$0.loops && mayPlay($0) }
        commands.oneShot = candidates.first { unitValue() < $0.entry.chance }?.entry.sound
        return commands
    }

    /// The loops that may play now, against those already asked to play.
    public mutating func refreshLoops(mayPlay: (RegionSound) -> Bool) -> RegionSoundCommands {
        let wanted = sounds.filter { $0.loops && mayPlay($0) }.map(\.entry.sound)
        var commands = RegionSoundCommands()
        commands.stopLoops = playingLoops.filter { !wanted.contains($0) }
        commands.startLoops = wanted.filter { !playingLoops.contains($0) }
        playingLoops = wanted
        return commands
    }

    /// One of `count` files, picked at random; 0 for an empty list.
    public mutating func pick(count: Int) -> Int {
        guard count > 1 else { return 0 }
        return Int(random.next() % UInt64(count))
    }

    private mutating func nextInterval() -> Float {
        let range = Self.rollInterval
        return range.lowerBound + unitValue() * (range.upperBound - range.lowerBound)
    }

    /// A value in [0, 1).
    private mutating func unitValue() -> Float {
        Float(random.next() >> 40) / Float(1 << 24)
    }
}
