// The commands that build cells, actors, and collision around a grid cell.

import ArgumentParser

public struct CellArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "cell",
        abstract: "Summarize a cell's references without Metal."
    )
    @OptionGroup public var global: GlobalOptions
    @OptionGroup public var grid: GridOptions
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp(
            "An interior cell editor ID, in place of a grid cell.",
            valueName: "edid"
        )
    )
    public var cell: String?
    @Flag(help: "List every reference.")
    public var refs = false

    public init() {}
}

public struct ActorArguments: ParsableCommand, Sendable {
    public static let configuration = CommandConfiguration(
        commandName: "actor",
        abstract: "Resolve how actors look, or how their values are derived.",
        subcommands: [Appearance.self, Values.self]
    )

    public init() {}

    public struct Appearance: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "appearance",
            abstract: "List placed actors around a cell and resolve how each one looks.",
            discussion: "Each base NPC_ resolves through its TPLT template chain to a skeleton, "
                + "body parts with slot masking, FaceGen paths, and reason-tagged skips."
        )
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var grid: GridOptions
        @Option(
            parsing: .unconditional,
            help: ArgumentHelp("Cells around the center.", valueName: "n")
        )
        public var radius: Int32 = 1
        @Option(
            parsing: .unconditional,
            help: ArgumentHelp(
                "Resolve one base NPC_ instead: FormID or editor ID.",
                valueName: "id"
            )
        )
        public var npc: String?

        public init() {}

        public func validate() throws {
            try OptionCheck.atLeast(radius, 0, "--radius")
        }
    }

    public struct Values: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "values",
            abstract: "Derive one NPC_'s base health, magicka, and stamina, or one RACE's values."
        )
        @OptionGroup public var global: GlobalOptions
        @Option(
            parsing: .unconditional,
            help: ArgumentHelp("The NPC_: FormID or editor ID.", valueName: "id")
        )
        public var npc: String?
        @Option(
            parsing: .unconditional,
            help: ArgumentHelp("The RACE: FormID or editor ID.", valueName: "id")
        )
        public var race: String?
        @Option(
            parsing: .unconditional,
            help: ArgumentHelp("The level PC-level-mult actors scale with.", valueName: "n")
        )
        public var playerLevel = 1

        public init() {}

        public func validate() throws {
            guard (npc == nil) != (race == nil) else {
                throw ValidationError("give --npc or --race")
            }
            try OptionCheck.atLeast(playerLevel, 1, "--player-level")
        }
    }
}

public struct CollisionArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "collision",
        abstract: "Sweep embedded NIF collision for the center cell's models and the grid."
    )
    @OptionGroup public var global: GlobalOptions
    @OptionGroup public var grid: GridOptions
    @Option(parsing: .unconditional, help: ArgumentHelp("Cells around the center.", valueName: "n"))
    public var radius: Int32 = 0

    public init() {}

    public func validate() throws {
        try OptionCheck.range(radius, 0 ... 10, "--radius")
    }
}

public struct InteriorArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "interior",
        abstract: "Go through a nearby door and back; render the arrival as a PNG.",
        discussion: "A check of the door transition. To look at a cell, use render or preview."
    )
    @OptionGroup public var global: GlobalOptions
    @OptionGroup public var grid: GridOptions
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Cells around the center to search for a door.", valueName: "n")
    )
    public var radius: Int32 = 16
    @Option(parsing: .unconditional, help: ArgumentHelp("The PNG to write.", valueName: "file"))
    public var out: String

    public init() {}

    public func validate() throws {
        try OptionCheck.range(radius, 0 ... 64, "--radius")
    }
}

public struct LODArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "lod",
        abstract: "Parse the LOD settings and sweep the .btr, .bto, .lst, and .btt files."
    )
    @OptionGroup public var global: GlobalOptions
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Worldspace editor ID. Default: Tamriel.", valueName: "edid")
    )
    public var worldspace: String?

    public init() {}
}
