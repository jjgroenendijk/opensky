// The game settings behind head tracking: turn speed, dead zones, limits, and the
// idle look-around. Vanilla values are the Creation Kit wiki's "Category:Settings"
// table; the units are OpenSky's reading. See docs/engine/head-tracking.md.

import Foundation
import OpenSkyGameData

/// When an actor glances away from what it looks at, and how far. Seconds and degrees.
nonisolated public struct HeadGlanceTiming: Equatable, Sendable {
    /// The smallest and largest glance, in degrees on each axis.
    public var offsetMin: Float
    public var offsetMax: Float
    /// Seconds into each cycle when the glance starts.
    public var pickNewOffset: Float
    /// Seconds one cycle lasts; the look is back on the target at its start.
    public var resetPosition: Float
    public var stayInOffsetMin: Float
    public var stayInOffsetMax: Float

    public init(
        offsetMin: Float, offsetMax: Float, pickNewOffset: Float, resetPosition: Float,
        stayInOffsetMin: Float, stayInOffsetMax: Float
    ) {
        self.offsetMin = offsetMin
        self.offsetMax = offsetMax
        self.pickNewOffset = pickNewOffset
        self.resetPosition = resetPosition
        self.stayInOffsetMin = stayInOffsetMin
        self.stayInOffsetMax = stayInOffsetMax
    }
}

nonisolated public struct HeadTrackingSettings: Equatable, Sendable {
    /// `fHeadTrackSpeedMin` and `fHeadTrackSpeedMax`: degrees per second.
    public var speedMin: Float = 60
    public var speedMax: Float = 200
    /// `fHeadTrackSpeedMinAngle` and `fHeadTrackSpeedMaxAngle`: the turn still to go, in
    /// degrees, at which the speed is the slowest and the fastest.
    public var speedMinAngle: Float = 5
    public var speedMaxAngle: Float = 10
    /// `fTrackDeadZoneXY` and `fTrackDeadZoneZ`: degrees a goal may move before the head follows.
    public var deadZoneXY: Float = 8
    public var deadZoneZ: Float = 8
    /// `fTrackXY`, `fTrackMinZ`, `fTrackMaxZ`: the largest yaw and pitch, in degrees.
    public var trackXY: Float = 60
    public var trackMinZ: Float = -60
    public var trackMaxZ: Float = 60
    /// `fAIHoldDefaultHeadTrackTimer`: seconds an actor keeps looking at the player after
    /// the player leaves its notice distance.
    public var holdDefault: Float = 5
    /// `fAIHeadTrack...`.
    public var idle = HeadGlanceTiming(
        offsetMin: 0, offsetMax: 0, pickNewOffset: 2, resetPosition: 4,
        stayInOffsetMin: 1, stayInOffsetMax: 2
    )
    /// `fAIHeadTrackDialogue...`; the one offset value is both the smallest and the largest.
    public var dialogue = HeadGlanceTiming(
        offsetMin: 0, offsetMax: 0, pickNewOffset: 2, resetPosition: 4,
        stayInOffsetMin: 1, stayInOffsetMax: 2
    )

    public static let vanilla = Self()

    public init() {}

    public var maximumYaw: Float {
        radians(max(trackXY, 0))
    }

    public var pitchRange: ClosedRange<Float> {
        radians(min(trackMinZ, trackMaxZ)) ... radians(max(trackMinZ, trackMaxZ))
    }

    /// Radians per second with `remaining` radians still to turn: the slow speed close to
    /// the goal, the fast one far from it, and a straight blend between.
    public func turnSpeed(remaining: Float) -> Float {
        let degrees = remaining * 180 / .pi
        let span = speedMaxAngle - speedMinAngle
        let blend = span > 0 ? min(max((degrees - speedMinAngle) / span, 0), 1)
            : degrees >= speedMaxAngle ? 1 : 0
        return radians(speedMin + (speedMax - speedMin) * blend)
    }

    /// True when `goal` is inside the dead zone around `look`.
    public func isInsideDeadZone(_ look: HeadLook, goal: HeadLook) -> Bool {
        abs(goal.yaw - look.yaw) <= radians(deadZoneXY)
            && abs(goal.pitch - look.pitch) <= radians(deadZoneZ)
    }

    private func radians(_ degrees: Float) -> Float {
        degrees * .pi / 180
    }

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("fHeadTrackSpeedMin", into: &settings, \.speedMin)
        store.read("fHeadTrackSpeedMax", into: &settings, \.speedMax)
        store.read("fHeadTrackSpeedMinAngle", into: &settings, \.speedMinAngle)
        store.read("fHeadTrackSpeedMaxAngle", into: &settings, \.speedMaxAngle)
        store.read("fTrackDeadZoneXY", into: &settings, \.deadZoneXY)
        store.read("fTrackDeadZoneZ", into: &settings, \.deadZoneZ)
        store.read("fTrackXY", into: &settings, \.trackXY)
        store.read("fTrackMinZ", into: &settings, \.trackMinZ)
        store.read("fTrackMaxZ", into: &settings, \.trackMaxZ)
        store.read("fAIHoldDefaultHeadTrackTimer", into: &settings, \.holdDefault)
        readGlance("fAIHeadTrack", into: &settings, \.idle, store: store)
        readGlance("fAIHeadTrackDialogue", into: &settings, \.dialogue, store: store)
        return settings
    }

    private static func readGlance(
        _ prefix: String, into settings: inout Self,
        _ keyPath: WritableKeyPath<Self, HeadGlanceTiming>, store: GameSettingStore
    ) {
        var timing = settings[keyPath: keyPath]
        if let value = store.number("\(prefix)OffsetRandomValue") {
            timing.offsetMin = value
            timing.offsetMax = value
        }
        store.read("\(prefix)OffsetRandomValueMin", into: &timing, \.offsetMin)
        store.read("\(prefix)OffsetRandomValueMax", into: &timing, \.offsetMax)
        store.read("\(prefix)PickNewOffsetTimer", into: &timing, \.pickNewOffset)
        store.read("\(prefix)ResetPositionTimer", into: &timing, \.resetPosition)
        store.read("\(prefix)StayInOffsetMin", into: &timing, \.stayInOffsetMin)
        store.read("\(prefix)StayInOffsetMax", into: &timing, \.stayInOffsetMax)
        settings[keyPath: keyPath] = timing
    }
}
