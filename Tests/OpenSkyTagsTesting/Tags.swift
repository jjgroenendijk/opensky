import Foundation
import Testing

/// The tags every test target shares. A test plan selects by
/// them, so the list is in `docs/tools/test-runs.md` too.
extension Tag {
    /// Needs a Metal device.
    @Tag public static var gpu: Self
    /// Takes seconds, not milliseconds, on a warm build.
    @Tag public static var slow: Self
    /// Walks a whole player-facing chain under `Tests/OpenSkyTests/Acceptance/`.
    @Tag public static var acceptance: Self
    /// A timing gate that only means something on an optimized build.
    @Tag public static var perf: Self
    /// Covers a file-format parser.
    @Tag public static var parser: Self
    /// A real-data test in the smoke set, the ones `make test-real` runs by default.
    @Tag public static var smoke: Self
}

/// Xcode 27 ignores a plan's `skippedTags`, so a plan names the tags to skip in
/// `OPENSKY_SKIPPED_TAGS` (`slow,gpu`) and each tagged test carries this trait.
extension Trait where Self == ConditionTrait {
    public static func unlessPlanSkips(_ tag: Tag) -> Self {
        .enabled("the test plan skips this tag") { !PlanSkippedTags.current.contains(tag) }
    }
}

enum PlanSkippedTags {
    static let current: Set<Tag> = {
        let names = ProcessInfo.processInfo.environment["OPENSKY_SKIPPED_TAGS"] ?? ""
        let known: [String: Tag] = ["gpu": .gpu, "slow": .slow]
        return Set(names.split(separator: ",")
            .compactMap { known[$0.trimmingCharacters(in: .whitespaces)] })
    }()
}
