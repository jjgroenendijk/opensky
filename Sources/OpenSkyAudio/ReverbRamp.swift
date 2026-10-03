// The reverb crossfade: the wet level moves toward the acoustic space's level
// at a fixed rate. A change of room first fades the old room out, then loads
// the new preset and fades it in. See docs/formats/sound-output-reverb.md.

import Foundation

nonisolated public struct ReverbRamp: Equatable, Sendable {
    /// dB per second: silent to 0 dB in one second.
    public static let rate: Float = 40

    public private(set) var target = ReverbSetting.off
    /// The preset the node has loaded, nil while off.
    public private(set) var room: ReverbRoom?
    /// The current wet level in dB.
    public private(set) var level = ReverbSetting.levelRange.lowerBound
    /// A fixed wet level in dB for listening tests; nil follows the ramp.
    public var wetOverride: Float?
    /// The preset last loaded into the node, so a ramp step does not reload it.
    var loadedRoom: ReverbRoom?

    public init() {}

    public var appliedLevel: Float {
        wetOverride.map { min(max($0, ReverbSetting.levelRange.lowerBound), 40) } ?? level
    }

    public mutating func setTarget(_ setting: ReverbSetting) {
        target = setting
        if room == nil {
            room = setting.room
        }
    }

    /// Moves the level one step. Returns true when the level or room changed.
    @discardableResult
    public mutating func advance(_ seconds: Float) -> Bool {
        let floor = ReverbSetting.levelRange.lowerBound
        let switching = room != target.room
        let goal = switching || target.isOff ? floor : target.level
        let step = Self.rate * (seconds.isFinite ? max(seconds, 0) : 0)
        let before = (room, level)
        level = goal > level ? min(level + step, goal) : max(level - step, goal)
        if switching, level <= floor {
            room = target.room
        }
        return before.0 != room || before.1 != level
    }
}
