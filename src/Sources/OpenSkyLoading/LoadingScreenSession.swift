// One loading screen, from the start of a transition until the world shows
// again: a minimum display time, then a fade. The timing rules and why:
// docs/engine/loading-screens.md.

import Foundation
public import OpenSkyFormatsESM
public import OpenSkyGameData
import simd

nonisolated public struct LoadingScreenSession: Equatable, Sendable {
    /// Long enough that a fast cell build shows a readable screen, not a
    /// one-frame flash.
    static let minimumSeconds = 1.5
    /// The game fades the world in from black over one second.
    public static let fadeSeconds = 1.0

    nonisolated public enum Phase: Equatable, Sendable {
        case showing
        case fading
        case finished
    }

    public let screen: ResolvedRecord<LoadScreen>?
    public let startedAt: Double
    public private(set) var readyAt: Double?
    /// The player's turn so far, inside the ONAM range.
    public private(set) var turnRadians: Float = 0
    /// The scene camera's field of view, in the game's own unit.
    public private(set) var fieldOfView = LoadingScreenScene.defaultFieldOfView

    public init(screen: ResolvedRecord<LoadScreen>?, startedAt: Double) {
        self.screen = screen
        self.startedAt = startedAt
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.screen?.id == rhs.screen?.id && lhs.startedAt == rhs.startedAt
            && lhs.readyAt == rhs.readyAt && lhs.turnRadians == rhs.turnRadians
            && lhs.fieldOfView == rhs.fieldOfView
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
    func opacity(at time: Double) -> Float {
        guard let fadeStart, time > fadeStart else { return 1 }
        return Float(max(0, 1 - (time - fadeStart) / Self.fadeSeconds))
    }

    /// The player's turn, in degrees, for the state readout.
    public var turnDegrees: Float {
        turnRadians * 180 / .pi
    }

    /// RNAM, in degrees.
    var initialRotationDegrees: SIMD3<Float> {
        SIMD3<Float>(screen?.record.initialRotation.map(SIMD3<Float>.init) ?? .zero)
    }

    /// Seconds the screen has shown, for the camera path.
    func elapsedSeconds(at time: Double) -> Double {
        max(0, time - startedAt)
    }

    /// The player turns the object about the scene's vertical axis. ONAM limits the
    /// turn only when it is narrower than a full turn each way; -180 and 180 are the
    /// defaults with no ONAM.
    public mutating func turn(byRadians radians: Float) {
        guard radians.isFinite else { return }
        var next = turnRadians + radians
        let range = screen?.record.rotationOffsetRange.map {
            SIMD2<Float>(Float(min($0.x, $0.y)), Float(max($0.x, $0.y)))
        } ?? SIMD2(-180, 180)
        if range.x > -180 || range.y < 180 {
            next = min(max(next, range.x * .pi / 180), range.y * .pi / 180)
        }
        turnRadians = next
    }

    /// A change that would leave the open limits is ignored.
    public mutating func changeFieldOfView(by amount: Float) {
        let next = fieldOfView + amount
        let limits = LoadingScreenScene.fieldOfViewLimits
        guard next > limits.low, next < limits.high else { return }
        fieldOfView = next
    }
}
