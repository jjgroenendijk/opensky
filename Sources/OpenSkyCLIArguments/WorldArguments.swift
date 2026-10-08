// The commands that build cells, actors, and collision around a grid cell.

import ArgumentParser

public struct CellArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "cell",
        abstract: "Summarize an exterior cell's references without Metal."
    )
    @OptionGroup public var global: GlobalOptions
    @OptionGroup public var grid: GridOptions
    @Flag(help: "List every reference.")
    public var refs = false

    public init() {}
}

public struct ActorArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "actor",
        abstract: "List placed actors around a cell and resolve how each one looks.",
        discussion: "Each base NPC_ resolves through its TPLT template chain to a skeleton, "
            + "body parts with slot masking, FaceGen paths, and reason-tagged skips."
    )
    @OptionGroup public var global: GlobalOptions
    @OptionGroup public var grid: GridOptions
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Cells around the center. Default: 1.", valueName: "n")
    )
    public var radius: String?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Resolve one base NPC_ directly.", valueName: "formid-or-edid")
    )
    public var npc: String?

    public init() {}
}

public struct ActorValuesArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "actor-values",
        abstract: "Derive one NPC_'s base health, magicka, and stamina, or one RACE's values.",
        usage: "openskycli actor-values (--npc <formid-or-edid> | --race <formid-or-edid>) "
            + "[--player-level <n>]"
    )
    @OptionGroup public var global: GlobalOptions
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("The NPC_ to derive.", valueName: "formid-or-edid")
    )
    public var npc: String?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("The RACE to report.", valueName: "formid-or-edid")
    )
    public var race: String?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Scales PC-level-mult actors. Default: 1.", valueName: "n")
    )
    public var playerLevel: String?

    public init() {}
}

public struct CollisionArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "collision",
        abstract: "Sweep embedded NIF collision for the center cell's models and the grid."
    )
    @OptionGroup public var global: GlobalOptions
    @OptionGroup public var grid: GridOptions
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Cells around the center.", valueName: "n")
    )
    public var radius: String?

    public init() {}
}

public struct InteriorArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "interior",
        abstract: "Enter the interior behind a nearby door, render the arrival, and come back."
    )
    @OptionGroup public var global: GlobalOptions
    @OptionGroup public var grid: GridOptions
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Cells around the center to search.", valueName: "n")
    )
    public var radius: String?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("The PNG to write.", valueName: "file")
    )
    public var out: String

    public init() {}
}

public struct LODArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "lod",
        abstract: "Parse the LOD settings and sweep the .btr, .bto, .lst, and .btt files."
    )
    @OptionGroup public var global: GlobalOptions
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Worldspace editor ID.", valueName: "edid")
    )
    public var worldspace: String?

    public init() {}
}
