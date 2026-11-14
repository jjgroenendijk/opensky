public import Foundation

/// Wall-clock times of the steps between the process start and a ready world.
nonisolated public struct AppStartMarks: Equatable, Sendable {
    /// The app's `main` started.
    public var mainEntered: Date?
    /// AppKit finished its launch and called the app delegate.
    public var launchFinished: Date?
    public var worldLoadStarted: Date?
    public var worldLoadFinished: Date?

    public init(
        mainEntered: Date? = nil, launchFinished: Date? = nil,
        worldLoadStarted: Date? = nil, worldLoadFinished: Date? = nil
    ) {
        self.mainEntered = mainEntered
        self.launchFinished = launchFinished
        self.worldLoadStarted = worldLoadStarted
        self.worldLoadFinished = worldLoadFinished
    }
}

/// One stretch of the app start, from the mark before it to its own mark.
nonisolated public enum AppStartPhase: String, CaseIterable, Sendable {
    /// The kernel start until `main`: loading the executable and its libraries.
    case beforeMain
    /// `main` until AppKit finished its launch.
    case appLaunch
    /// The launch until the world data load starts.
    case beforeWorldLoad
    case worldLoad
    /// The world data load until the session start, such as making the game window.
    case beforeSession
    /// Renderer setup, game systems, and the wait for the first frame.
    case session
    /// The first frame until the world is ready: the start area streams in behind the cover.
    case startArea
}

nonisolated extension AppStartPhase {
    /// Splits `start ... ready` at each known mark, in order, so the phases add up
    /// to the whole time. A phase whose end mark is missing is left out, and the
    /// phase after it starts at the mark before it.
    public static func split(
        from start: Date,
        to ready: Date,
        ends: [Self: Date]
    ) -> [Self: Double] {
        var phases: [Self: Double] = [:]
        var previous = start
        for phase in allCases {
            guard let end = phase == .startArea ? ready : ends[phase] else { continue }
            let clamped = min(max(end, previous), ready)
            phases[phase] = clamped.timeIntervalSince(previous) * millisecondsPerSecond
            previous = clamped
        }
        return phases
    }

    private static let millisecondsPerSecond = 1000.0
}
