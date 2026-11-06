// A `BSLODTriShape` cross-fades a detail level change over one second, as the game does
// (docs/engine/graphics-options.md).

/// The detail level of one reference and the change that runs toward it. A coarser level
/// draws a prefix of the finer level's triangles, so only the finer level's extra
/// triangles fade.
nonisolated public struct MeshLODFade: Equatable, Sendable {
    public static let seconds: Float = 1

    /// The level the reference changes to, or has.
    public private(set) var level: Int
    /// The level it changes from; equal to `level` once no change runs.
    public private(set) var previous: Int
    /// 0 at the start of a change, 1 when it is done.
    public private(set) var progress: Float

    public init(level: Int) {
        self.level = level
        previous = level
        progress = 1
    }

    /// The state `seconds` later, with `target` as the level the distance now asks for.
    /// A change that turns back runs the rest of the way in reverse, so nothing pops.
    public func stepped(toward target: Int, seconds: Float) -> Self {
        var next = self
        if target != level {
            next.progress = target == previous && progress < 1 ? 1 - progress : 0
            next.previous = level
            next.level = target
        }
        let step = seconds.isFinite ? max(seconds, 0) / Self.seconds : 0
        next.progress = min(next.progress + step, 1)
        if next.progress >= 1 {
            next.previous = next.level
        }
        return next
    }

    /// The level whose triangles draw whole: the coarser one while a change runs.
    public var drawnLevel: Int {
        max(level, previous)
    }

    /// While a change runs: the finer level, whose extra triangles draw on top of
    /// `drawnLevel`, and their dissolve, 0 whole to 1 gone.
    public var fading: (finer: Int, dissolve: Float)? {
        guard level != previous else { return nil }
        let coarsening = level > previous
        return (min(level, previous), coarsening ? progress : 1 - progress)
    }
}
