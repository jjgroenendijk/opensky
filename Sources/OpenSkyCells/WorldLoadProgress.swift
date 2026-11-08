// The stages of the world data load and how each one reports its time. The
// launcher lists them while it loads; Instruments shows them as signposts.

import Foundation
import OpenSkyFormatsCore
public import OpenSkyWorldInterface
import OSLog

/// Times each stage, marks it as a signpost interval, and reports its start and end.
/// Stages run on several threads at once, so `report` must be thread-safe.
nonisolated public struct WorldLoadProgress: Sendable {
    private static let signposter = OSSignposter(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "WorldLoad"
    )

    public static let silent = WorldLoadProgress { _ in }

    private let report: @Sendable (WorldLoadEvent) -> Void

    public init(report: @escaping @Sendable (WorldLoadEvent) -> Void) {
        self.report = report
    }

    /// Throws `CancellationError` instead of starting a stage once the load is cancelled.
    public func measure<Value>(
        _ stage: WorldLoadStage,
        _ body: () throws -> Value
    ) throws -> Value {
        try Task.checkCancellation()
        report(WorldLoadEvent(stage: stage, kind: .started))
        let signpost = Self.signposter.beginInterval(
            "stage",
            id: Self.signposter.makeSignpostID(),
            "\(stage.rawValue, privacy: .public)"
        )
        let start = Stopwatch()
        let value = try body()
        Self.signposter.endInterval("stage", signpost)
        report(WorldLoadEvent(stage: stage, kind: .finished(start.elapsed)))
        return value
    }
}
