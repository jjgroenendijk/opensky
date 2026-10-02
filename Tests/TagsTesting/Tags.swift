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
}
