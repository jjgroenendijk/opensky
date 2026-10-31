// One loading screen, from the start of a transition until the world shows
// again: a minimum display time, then a fade. The timing rules and why:
// docs/engine/loading-screens.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import simd

nonisolated public struct LoadingScreenSession: Equatable, Sendable {
    /// Long enough that a fast cell build shows a readable screen, not a
    /// one-frame flash.
    public static let minimumSeconds = 1.5
    public static let fadeSeconds = 0.4

    nonisolated public enum Phase: Equatable, Sendable {
        case showing
        case fading
        case finished
    }

    public let screen: ResolvedRecord<LoadScreen>?
    public let startedAt: Double
    public private(set) var readyAt: Double?
    /// The player's turn so far, inside the ONAM range.
    public private(set) var turnDegrees: Float = 0

    public init(screen: ResolvedRecord<LoadScreen>?, startedAt: Double) {
        self.screen = screen
        self.startedAt = startedAt
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.screen?.id == rhs.screen?.id && lhs.startedAt == rhs.startedAt
            && lhs.readyAt == rhs.readyAt && lhs.turnDegrees == rhs.turnDegrees
    }

    /// The destination finished building. Only the first call counts.
    public mutating func markReady(at time: Double) {
        guard readyAt == nil else { return }
        readyAt = max(time, startedAt)
    }

    /// When the fade starts: once the destination is ready and the minimum passed.
    public var fadeStart: Double? {
        readyAt.map { max($0, startedAt + Self.minimumSeconds) }
    }

    public func phase(at time: Double) -> Phase {
        guard let fadeStart, time >= fadeStart else { return .showing }
        return time - fadeStart >= Self.fadeSeconds ? .finished : .fading
    }

    /// Cover opacity: 1 while showing, falling to 0 over the fade.
    public func opacity(at time: Double) -> Float {
        guard let fadeStart, time > fadeStart else { return 1 }
        return Float(max(0, 1 - (time - fadeStart) / Self.fadeSeconds))
    }

    /// The object's rotation in degrees: RNAM plus the player's turn about Z.
    public var objectRotationDegrees: SIMD3<Float> {
        let initial = SIMD3<Float>(screen?.record.initialRotation.map(SIMD3<Float>.init) ?? .zero)
        return initial + SIMD3(0, 0, turnDegrees)
    }

    /// Seconds the screen has shown, for the camera path.
    public func elapsedSeconds(at time: Double) -> Double {
        max(0, time - startedAt)
    }

    /// The player turns the object; ONAM limits how far. No range means no turn.
    public mutating func turn(byDegrees degrees: Float) {
        guard degrees.isFinite, let range = screen?.record.rotationOffsetRange else { return }
        let low = Float(min(range.x, range.y))
        let high = Float(max(range.x, range.y))
        turnDegrees = min(max(turnDegrees + degrees, low), high)
    }
}
