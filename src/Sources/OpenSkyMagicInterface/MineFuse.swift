// A mine waits armed until a hostile living actor comes near, then burns a short fuse.
// Runes and alternate-trigger projectiles share it. See docs/engine/explosions.md#mines.

import Foundation
public import OpenSkyFormatsESM

nonisolated public struct MineFuse: Equatable, Sendable {
    /// Seconds from the trigger to the blast.
    public static let triggerSeconds: Float = 0.2
    /// The blink interval while more than `fastBlinkWindow` seconds are left.
    static let slowBlink: Float = 0.25
    /// The blink interval the light reaches as the fuse runs out.
    static let fastBlink: Float = 0.1
    static let fastBlinkWindow: Float = 2

    /// Seconds left on the fuse; nil while the mine still waits.
    public private(set) var remaining: Float?
    /// The actor that started the fuse.
    public private(set) var trigger: ReferenceKey?
    /// A failed roll: the player can no longer set this mine off.
    public private(set) var ignoresPlayer = false
    /// Whether the blinking light is on now.
    public private(set) var isLit = false
    private var blinkClock: Float = 0

    public init() {}

    public var isBurning: Bool {
        remaining != nil
    }

    /// Starts the fuse for `actor`, once. The player must pass `playerRoll`, a check that
    /// returns false on a failed roll; a failure means this mine never checks the player again.
    public mutating func notice(_ actor: ReferenceKey, playerRoll: () -> Bool) {
        guard remaining == nil else { return }
        if actor == .player {
            guard !ignoresPlayer else { return }
            guard playerRoll() else {
                ignoresPlayer = true
                return
            }
        }
        remaining = Self.triggerSeconds
        trigger = actor
    }

    /// Burns `seconds` of the fuse and blinks the light. True when the mine goes off.
    public mutating func burn(_ seconds: Float) -> Bool {
        guard let left = remaining else { return false }
        let step = seconds.isFinite ? max(seconds, 0) : 0
        blinkClock += step
        if blinkClock >= Self.blinkInterval(remaining: left) {
            blinkClock = 0
            isLit.toggle()
        }
        remaining = left - step
        return left - step <= 0
    }

    /// Every 0.25 seconds, speeding up to every 0.1 seconds over the last 2 seconds.
    public static func blinkInterval(remaining: Float) -> Float {
        guard remaining < fastBlinkWindow else { return slowBlink }
        let share = max(remaining, 0) / fastBlinkWindow
        return fastBlink + (slowBlink - fastBlink) * share
    }

    /// Whether a roll in 0 ..< 100 sets the mine off for the player, at `chance` percent.
    public static func playerPasses(chance: Float, roll: Float) -> Bool {
        roll < chance
    }
}

/// A placed rune as the renderer draws it: its spell's projectile model where it waits,
/// with the projectile's light on while the fuse's blink is lit.
nonisolated public struct RuneMarker: Equatable, Sendable {
    public let position: SIMD3<Float>
    /// The spell's `PROJ`, which holds the model and the light.
    public let projectile: FormID?
    public let isLit: Bool

    public init(position: SIMD3<Float>, projectile: FormID?, isLit: Bool) {
        self.position = position
        self.projectile = projectile
        self.isLit = isLit
    }
}
