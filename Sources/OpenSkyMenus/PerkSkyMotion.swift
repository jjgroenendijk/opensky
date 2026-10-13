// How the perk sky camera moves over time: the turn around the ring, the move in to
// a tree and back, and the opening rise. See docs/engine/perk-sky.md.

import Foundation

nonisolated public struct PerkSkyMotion: Equatable, Sendable {
    /// Seconds for the move between the ring and a tree.
    public static let treeSeconds: Float = 0.5

    public private(set) var yawDegrees: Float
    public private(set) var treeBlend: Float = 0
    /// 0 to 1 through the dome's `CameraIntro`; the movie's `MoveCamera` sets it.
    public var introAlpha: Float = 0
    private var turnStarted: Double?
    private var lastTick: Double?

    public init(slot: Int) {
        yawDegrees = Float(slot) * PerkSkyLayout.slotDegrees
    }

    /// Steps toward `slot` and the ring or tree view. The turn speeds up to
    /// `fStatsRotationSpeedMax` over `fStatsRotationRampTime`, and takes the short way.
    public mutating func update(
        now: Double, slot: Int, slotCount: Int, inTree: Bool, settings: PerkSkySettings
    ) {
        let seconds = Float(max(0, min(0.25, now - (lastTick ?? now))))
        lastTick = now
        let full = Float(max(1, slotCount)) * PerkSkyLayout.slotDegrees
        var remaining = (Float(slot) * PerkSkyLayout.slotDegrees - yawDegrees)
            .truncatingRemainder(dividingBy: full)
        if remaining > full / 2 {
            remaining -= full
        } else if remaining < -full / 2 {
            remaining += full
        }
        if abs(remaining) < 0.01 {
            turnStarted = nil
            yawDegrees = Float(slot) * PerkSkyLayout.slotDegrees
        } else {
            let started = turnStarted ?? now
            turnStarted = started
            let ramp = max(0.001, settings.rotationRampTime)
            let speed = settings.rotationSpeedMax * min(1, max(0.1, Float(now - started) / ramp))
            let turn = min(abs(remaining), speed * seconds)
            yawDegrees += remaining < 0 ? -turn : turn
        }
        let step = seconds / Self.treeSeconds
        treeBlend = inTree ? min(1, treeBlend + step) : max(0, treeBlend - step)
    }
}
