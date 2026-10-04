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
    /// How fast the object turns inside its ONAM range, degrees per second.
    public static let turnDegreesPerSecond: Float = 6

    nonisolated public enum Phase: Equatable, Sendable {
        case showing
        case fading
        case finished
    }

    public let screen: ResolvedRecord<LoadScreen>?
    public let startedAt: Double
    public private(set) var readyAt: Double?

    public init(screen: ResolvedRecord<LoadScreen>?, startedAt: Double) {
        self.screen = screen
        self.startedAt = startedAt
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.screen?.id == rhs.screen?.id && lhs.startedAt == rhs.startedAt
            && lhs.readyAt == rhs.readyAt
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

    /// The object's rotation in degrees: RNAM, plus a Z turn that moves back
    /// and forth across the ONAM range. No range means no turn.
    public func objectRotationDegrees(at time: Double) -> SIMD3<Float> {
        let initial = SIMD3<Float>(screen?.record.initialRotation.map(SIMD3<Float>.init) ?? .zero)
        guard let range = screen?.record.rotationOffsetRange else { return initial }
        let low = Float(min(range.x, range.y))
        let high = Float(max(range.x, range.y))
        let span = high - low
        guard span > 0 else { return initial + SIMD3(0, 0, low) }
        let travel = Float(time - startedAt) * Self.turnDegreesPerSecond
        let cycle = travel.truncatingRemainder(dividingBy: 2 * span)
        let offset = cycle <= span ? cycle : 2 * span - cycle
        return initial + SIMD3(0, 0, low + offset)
    }
}
