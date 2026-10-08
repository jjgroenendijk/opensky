// `swf` menu drivers: each runs one menu movie through its bridge against seeded or
// real records and prints what the movie built.

import ArgumentParser

/// `--ticks` and `--down`, which every menu driver takes. The CLI checks the numbers.
public struct MenuDriveOptions: ParsableArguments, Sendable {
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Frames to run before reading the movie.", valueName: "n")
    )
    public var ticks: String?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Move the selection down this many rows.", valueName: "n")
    )
    public var down: String?

    public init() {}
}

/// `--capture`, `--then`, and `--dump`, the movie probe options.
public struct MovieProbeOptions: ParsableArguments, Sendable {
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Host functions to print calls of.", valueName: "names")
    )
    public var capture: String?
    @Option(parsing: .unconditional, help: ArgumentHelp("Steps to run.", valueName: "steps"))
    public var then: String?
    @Option(parsing: .unconditional, help: ArgumentHelp("Nodes to print.", valueName: "paths"))
    public var dump: String?

    public init() {}
}

extension SWFArguments {
    public struct InventoryMenu: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "inventory-menu",
            abstract: "Drive the inventory menu with a seeded inventory; print its rows."
        )
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var drive: MenuDriveOptions
        @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "n"))
        public var right: String?

        public init() {}
    }

    public struct QuestJournal: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "quest-journal",
            abstract: "Drive the quest journal against one quest; print its rows."
        )
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var drive: MenuDriveOptions
        @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "edid"))
        public var quest: String?
        @Flag(help: "Resolve every field out of the string tables.")
        public var text = false
        @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "completed|failed"))
        public var objectiveState: String?
        @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "n"))
        public var probeRows: String?

        public init() {}
    }

    public struct ContainerMenu: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "container-menu",
            abstract: "Drive the container or barter menu; print rows, purses, and prices."
        )
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var drive: MenuDriveOptions
        @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "container|barter"))
        public var mode: String?
        @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "container|player"))
        public var side: String?
        @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "n"))
        public var transfer: String?

        public init() {}
    }

    public struct SystemMenu: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "system-menu",
            abstract: "Open the System page, start one state, and print GameDelegate calls."
        )
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var probe: MovieProbeOptions
        @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "name"))
        public var state = "SETTINGS_CATEGORY_STATE"
        @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "path"))
        public var focus: String?
        @Option(parsing: .unconditional, help: ArgumentHelp("A list row to accept."))
        public var row: Int?
        @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "n"))
        public var ticks = 20

        public init() {}
    }

    public struct MovieProbe: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "movie-probe",
            abstract: "Start any movie, run steps, and print host calls and nodes.",
            discussion: "Steps, split by ';', are call:<path>:<method>[:<JSON args>], "
                + "focus:<path>, or key:<code>."
        )
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var probe: MovieProbeOptions
        @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "path"))
        public var movie: String
        @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "n"))
        public var ticks = 10

        public init() {}
    }

    public struct DialogueMenu: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "dialogue-menu",
            abstract: "Drive the dialogue menu against real DIAL and INFO records."
        )
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var drive: MenuDriveOptions
        @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "n"))
        public var rows: String?
        @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "n"))
        public var probeRows: String?
        @Flag(help: "Resolve every field out of the string tables.")
        public var text = false
        @Flag(help: "Speak the selected topic.")
        public var speak = false

        public init() {}
    }
}
