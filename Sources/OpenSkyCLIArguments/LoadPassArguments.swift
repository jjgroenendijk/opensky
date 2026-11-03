// `load-pass`: the benchmark's cold and warm cell builds without the app.

import ArgumentParser

public struct LoadPassArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "load-pass",
        abstract: "Time the benchmark's cold and warm cell builds of one scene, without the app.",
        discussion: "Builds the scene's cells with a new builder and empty caches, then again "
            + "with full caches, and prints each pass split into load phases. By default the "
            + "builder reads only the archives, as before the asset cache is built; "
            + "--asset-cache reads the cache like the game. --evict drops the game data and "
            + "the asset cache from the page cache before each cold pass."
    )
    @OptionGroup public var global: GlobalOptions
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("The benchmark scene id. Default: whiterun.", valueName: "id")
    )
    public var scene = "whiterun"
    @Option(parsing: .unconditional, help: ArgumentHelp("Passes to run, 1 to 20. Default: 1."))
    public var runs = 1
    @Flag(help: "Decode one asset at a time, as with loading.parallelDecode off.")
    public var serial = false
    @Flag(help: "Read the asset cache, as the game does.")
    public var assetCache = false
    @Flag(help: "Drop the game data and the asset cache from the page cache before each cold pass.")
    public var evict = false
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp(
            "Turn load optimisations off: comma-separated names, or all.", valueName: "names"
        )
    )
    public var off: CommaList?

    public init() {}

    public func validate() throws {
        guard (1 ... 20).contains(runs) else {
            throw ValidationError("--runs takes 1 to 20")
        }
    }
}
