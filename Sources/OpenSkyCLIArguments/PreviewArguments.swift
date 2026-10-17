// The offscreen preview of one record, reference, cell, or mesh.

import ArgumentParser

public struct PreviewArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "preview",
        abstract: "Render one record, reference, cell, or mesh offscreen, with a JSON report.",
        discussion: "Give one of --record, --ref, --mesh, --cell, or --worldspace with --x "
            + "and --y. With --record, --ref, or --mesh, a cell option names the cell it "
            + "stands in, and the stage becomes cell. A view that draws nothing exits 1."
    )
    @OptionGroup public var global: GlobalOptions
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("A base record: FormID or editor ID.", valueName: "id")
    )
    public var record: String?
    @Option(
        name: .customLong("ref"), parsing: .unconditional,
        help: ArgumentHelp("A placed reference: FormID or editor ID.", valueName: "id")
    )
    public var reference: String?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("A mesh path, such as meshes\\clutter\\bucket01.nif.", valueName: "path")
    )
    public var mesh: String?
    @Option(parsing: .unconditional, help: ArgumentHelp("A cell editor ID.", valueName: "edid"))
    public var cell: String?
    @OptionGroup public var grid: GridOptions
    @Option(parsing: .unconditional, help: ArgumentHelp("studio or cell.", valueName: "stage"))
    public var stage: String?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("A reference to frame, or to stand the record on.", valueName: "id")
    )
    public var focus: String?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("all, or front,side,back,top,three-quarter.", valueName: "list")
    )
    public var angles: String?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Degrees from the front.", valueName: "deg")
    )
    public var yaw: String?
    @Option(parsing: .unconditional, help: ArgumentHelp("Degrees above.", valueName: "deg"))
    public var pitch: String?
    @Option(parsing: .unconditional, help: ArgumentHelp("Game units.", valueName: "units"))
    public var distance: String?
    @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "WxH"))
    public var size: String?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("An hour from 0 to 24. Default: 13.", valueName: "hour")
    )
    public var timeOfDay: String?
    @Option(parsing: .unconditional, help: ArgumentHelp("Force a weather.", valueName: "edid"))
    public var weather: String?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp(
            "Turn surface shading terms off: comma-separated names, or all.",
            valueName: "terms"
        )
    )
    public var shadingOff: String?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Default: .logs/preview/<UTC time>/.", valueName: "dir")
    )
    public var out: String?

    public init() {}
}
