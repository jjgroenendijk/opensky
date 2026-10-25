// `menu`: each subcommand runs one vanilla menu movie through its bridge against seeded or
// real records and prints what the movie built. `swf movie-probe` runs any movie.

import ArgumentParser

/// `--ticks` and `--down`, which every menu driver takes.
public struct MenuDriveOptions: ParsableArguments, Sendable {
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Frames to run before reading the movie.", valueName: "n")
    )
    public var ticks = 20
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Move the selection down this many rows.", valueName: "n")
    )
    public var down = 0

    public init() {}

    public func validate() throws {
        try OptionCheck.atLeast(ticks, 0, "--ticks")
        try OptionCheck.atLeast(down, 0, "--down")
    }
}

/// `--capture`, `--then`, and `--dump`, the movie probe options.
public struct MovieProbeOptions: ParsableArguments, Sendable {
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Host functions to print calls of, comma-separated.", valueName: "names")
    )
    public var capture: String?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Steps to run, split by ';'.", valueName: "steps")
    )
    public var then: String?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Nodes to print, comma-separated.", valueName: "paths")
    )
    public var dump: String?

    public init() {}
}

public struct MenuArguments: ParsableCommand, Sendable {
    public static let configuration = CommandConfiguration(
        commandName: "menu",
        abstract: "Drive one vanilla menu movie through its bridge and print what it built.",
        subcommands: [
            Inventory.self, QuestJournal.self, Container.self, System.self, Dialogue.self
        ]
    )

    public init() {}

    public struct Inventory: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "inventory",
            abstract: "Drive the inventory menu with a seeded inventory; print its rows."
        )
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var drive: MenuDriveOptions
        @Option(
            parsing: .unconditional,
            help: ArgumentHelp("Move to this many categories to the right.", valueName: "n")
        )
        public var right = 0

        public init() {}

        public func validate() throws {
            try OptionCheck.atLeast(right, 0, "--right")
        }
    }

    public struct QuestJournal: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "quest-journal",
            abstract: "Drive the quest journal against one quest; print its rows."
        )
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var drive: MenuDriveOptions
        @Option(
            parsing: .unconditional,
            help: ArgumentHelp("The quest editor ID.", valueName: "edid")
        )
        public var quest: String?
        @Flag(help: "Resolve every field out of the string tables.")
        public var text = false
        @Option(parsing: .unconditional, help: ArgumentHelp("Mark the objectives as this."))
        public var objectiveState: ObjectiveStateName?
        @Option(
            parsing: .unconditional,
            help: ArgumentHelp("Print this many rows of the probe list.", valueName: "n")
        )
        public var probeRows: Int?

        public init() {}

        public func validate() throws {
            try OptionCheck.atLeast(probeRows, 0, "--probe-rows")
        }
    }

    public struct Container: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "container",
            abstract: "Drive the container or barter menu; print rows, purses, and prices."
        )
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var drive: MenuDriveOptions
        @Option(parsing: .unconditional, help: ArgumentHelp("Open it as a container or a barter."))
        public var mode = ContainerMenuMode.container
        @Option(parsing: .unconditional, help: ArgumentHelp("The list that has focus."))
        public var side = ContainerMenuSide.container
        @Option(
            parsing: .unconditional,
            help: ArgumentHelp("Move the selected item this many times.", valueName: "n")
        )
        public var transfer = 0

        public init() {}

        public func validate() throws {
            try OptionCheck.atLeast(transfer, 0, "--transfer")
        }
    }

    public struct System: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "system",
            abstract: "Open the System page, start one state, and print GameDelegate calls."
        )
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var probe: MovieProbeOptions
        @Option(
            parsing: .unconditional,
            help: ArgumentHelp("The page state to start.", valueName: "name")
        )
        public var state = "SETTINGS_CATEGORY_STATE"
        @Option(
            parsing: .unconditional,
            help: ArgumentHelp("The node to focus first.", valueName: "path")
        )
        public var focus: String?
        @Option(
            parsing: .unconditional,
            help: ArgumentHelp("A list row to accept.", valueName: "n")
        )
        public var row: Int?
        @Option(parsing: .unconditional, help: ArgumentHelp("Frames to run.", valueName: "n"))
        public var ticks = 20

        public init() {}

        public func validate() throws {
            try OptionCheck.atLeast(row, 0, "--row")
            try OptionCheck.atLeast(ticks, 0, "--ticks")
        }
    }

    public struct Dialogue: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "dialogue",
            abstract: "Drive the dialogue menu against real DIAL and INFO records."
        )
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var drive: MenuDriveOptions
        @Option(parsing: .unconditional, help: ArgumentHelp("Topic rows to seed.", valueName: "n"))
        public var rows = 6
        @Option(
            parsing: .unconditional,
            help: ArgumentHelp("Print this many rows of the probe list.", valueName: "n")
        )
        public var probeRows: Int?
        @Flag(help: "Resolve every field out of the string tables.")
        public var text = false
        @Flag(help: "Speak the selected topic.")
        public var speak = false

        public init() {}

        public func validate() throws {
            try OptionCheck.atLeast(rows, 1, "--rows")
            try OptionCheck.atLeast(probeRows, 0, "--probe-rows")
        }
    }
}

extension SWFArguments {
    public struct MovieProbe: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "movie-probe",
            abstract: "Start any movie, run steps, and print host calls and nodes.",
            discussion: "Steps, split by ';', are call:<path>:<method>[:<JSON args>], "
                + "focus:<path>, or key:<code>."
        )
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var probe: MovieProbeOptions
        @Option(
            parsing: .unconditional,
            help: ArgumentHelp("The movie's archive path.", valueName: "path")
        )
        public var movie: String
        @Option(parsing: .unconditional, help: ArgumentHelp("Frames to run.", valueName: "n"))
        public var ticks = 10

        public init() {}

        public func validate() throws {
            try OptionCheck.atLeast(ticks, 0, "--ticks")
        }
    }
}
