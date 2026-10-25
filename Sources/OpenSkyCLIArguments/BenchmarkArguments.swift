// `benchmark`: the cinematic tour in the app's live window.

import ArgumentParser

public struct BenchmarkArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "benchmark",
        abstract: "Fly the benchmark tour in the app and print its frame, GPU, and load times.",
        discussion: "Opens OpenSky.app, which flies a camera through cities, wilderness, "
            + "interiors, and DLC worldspaces, then quits. result.json and summary.txt go to "
            + "--out. --set changes player settings for this run only, e.g. "
            + "--set rendering.renderScale=1,rendering.gpuCulling=off. Exits 1 when a scene "
            + "fails. 'game benchmark' runs the same tour in an app that is already open."
    )
    @OptionGroup public var global: GlobalOptions
    @Option(parsing: .unconditional, help: ArgumentHelp("The scene set. Default: standard."))
    public var preset: BenchmarkPresetName?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Scene ids, comma-separated.", valueName: "ids")
    )
    public var scenes: CommaList?
    @Flag(help: "Print the scenes and exit.")
    public var list = false
    @Flag(help: "Start with the overlay hidden.")
    public var noOverlay = false
    @Option(parsing: .unconditional, help: ArgumentHelp("The run folder.", valueName: "dir"))
    public var out: String?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Write a GPU trace of this scene.", valueName: "scene")
    )
    public var capture: String?
    @Option(
        name: .customLong("set"), parsing: .unconditional,
        help: ArgumentHelp(
            "Player settings for this run, comma-separated.",
            valueName: "id=value,..."
        )
    )
    public var settings: CommaList?
    @Flag(help: "Save PNGs of the start, middle, and end of each scene into the run folder.")
    public var screenshots = false
    @Flag(help: "Run in a window instead of full screen.")
    public var windowed = false
    @Flag(help: "Skip the cold and warm load of the first scene.")
    public var noLoadPasses = false
    @Flag(help: "Drop the game data from the page cache first, so the loads read the disk.")
    public var evict = false
    @Flag(help: "Leave the app open after the tour.")
    public var keepOpen = false
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp(
            "The app to open. Default: the build of this checkout.",
            valueName: "path"
        )
    )
    public var app: String?

    public init() {}
}
