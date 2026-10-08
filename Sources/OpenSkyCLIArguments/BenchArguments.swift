// `bench`: the sustained render, the fly path, and the walk path.

import ArgumentParser

/// The budgets only the fly path and the plain render take. `--walk-path` rejects them.
public struct BenchBudgetOptions: ParsableArguments, Sendable {
    @Option(parsing: .unconditional, help: ArgumentHelp("Frames to render.", valueName: "n"))
    public var frames: String?
    @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "f"))
    public var footprintCapMb: String?
    @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "f"))
    public var collisionBuildBudgetMs: String?
    @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "f"))
    public var actorBuildBudgetMs: String?
    @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "f"))
    public var animationBudgetMs: String?
    @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "f"))
    public var shadowBudgetMs: String?
    @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "f"))
    public var scriptBudgetMs: String?

    public init() {}

    /// The given options, by flag name, so the walk path can reject them.
    public var given: [(flag: String, value: String?)] {
        [
            ("--frames", frames), ("--footprint-cap-mb", footprintCapMb),
            ("--collision-build-budget-ms", collisionBuildBudgetMs),
            ("--actor-build-budget-ms", actorBuildBudgetMs),
            ("--animation-budget-ms", animationBudgetMs),
            ("--shadow-budget-ms", shadowBudgetMs), ("--script-budget-ms", scriptBudgetMs)
        ]
    }
}

public struct BenchArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "bench",
        abstract: "Sustained offscreen render; fail when the frame times miss the budget.",
        discussion: "--fly-path scripts east and north cell crossings through the real "
            + "streamer and checks memory, builds, actors, and living systems. --walk-path "
            + "walks the fixed M4 route: terrain, farm stairs, an interior, and back."
    )
    @OptionGroup public var global: GlobalOptions
    @OptionGroup public var grid: GridOptions
    @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "WxH"))
    public var size: String?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Frame budget. Default: 33.33.", valueName: "f")
    )
    public var budgetMs: String?
    @Flag(help: "Fly across cells through the real streamer.")
    public var flyPath = false
    @Flag(help: "Walk the fixed M4 route.")
    public var walkPath = false
    @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "file"))
    public var out: String?
    @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "n"))
    public var maxFrames: String?
    @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "f"))
    public var audioBudgetMs: String?
    @Flag(help: "Build the first distant LOD ring after the near grid, as a baseline.")
    public var noLodPrebuild = false
    @OptionGroup public var budgets: BenchBudgetOptions
    @OptionGroup public var assets: AssetLoadArguments

    public init() {}
}
