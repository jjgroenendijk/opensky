// The commands that read the load order's records, settings, and saves without Metal.

import ArgumentParser

/// `--worldspace`, `--x`, and `--y`: the target exterior cell.
public struct GridOptions: ParsableArguments, Sendable {
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Worldspace editor ID. Default: Tamriel.", valueName: "edid")
    )
    public var worldspace: String?
    @Option(parsing: .unconditional, help: ArgumentHelp("Cell grid X. Default: 6.", valueName: "n"))
    public var x: Int32?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Cell grid Y. Default: -2.", valueName: "n")
    )
    public var y: Int32?

    public init() {}
}

public struct PluginsArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "plugins",
        abstract: "Print the resolved plugin load order and the plugins.txt it came from.",
        discussion: "OPENSKY_PLUGINS_TXT overrides the search."
    )
    @OptionGroup public var global: GlobalOptions

    public init() {}
}

public struct RecordArguments: ParsableCommand, Sendable {
    public static let configuration = CommandConfiguration(
        commandName: "record",
        abstract: "Show one record by FormID or editor ID.",
        subcommands: [Show.self]
    )

    public init() {}

    public struct Show: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "show",
            abstract: "Print the winning record: header, decoded view, and fields."
        )
        @OptionGroup public var global: GlobalOptions
        @Argument(help: ArgumentHelp(
            "A FormID in hex, such as 0x3C, or an editor ID. An editor ID scans every plugin.",
            valueName: "id"
        ))
        public var id: String

        public init() {}
    }
}

public struct ESSArguments: ParsableCommand, Sendable {
    public static let configuration = CommandConfiguration(
        commandName: "ess",
        abstract: "Inspect a Skyrim save read-only, or list the saves in a folder.",
        subcommands: [Show.self, List.self]
    )

    public init() {}

    public struct Show: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "show",
            abstract: "Print a save and run its import against the load order."
        )
        @OptionGroup public var global: GlobalOptions
        @Argument(help: ArgumentHelp("The .ess file.", valueName: "save.ess"))
        public var save: String
        @Flag(help: "Skip the load order and the import.")
        public var offline = false

        public init() {}
    }

    public struct List: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "Print the header of each save in a folder."
        )
        @OptionGroup public var global: GlobalOptions
        @Argument(help: ArgumentHelp("The folder that holds the saves.", valueName: "folder"))
        public var folder: String

        public init() {}
    }
}

public struct GMSTArguments: ParsableCommand, Sendable {
    public static let configuration = CommandConfiguration(
        commandName: "gmst",
        abstract: "Print resolved game settings with the plugin each came from.",
        subcommands: [
            Subject<MovementSubject>.self, Subject<CombatSubject>.self,
            Subject<ArcherySubject>.self, Subject<DetectionSubject>.self, List.self
        ]
    )

    public init() {}

    /// One subsystem's settings; each subject is its own subcommand.
    public struct Subject<Kind: GMSTSubjectKind>: CLICommandArguments {
        public static var configuration: CommandConfiguration {
            CommandConfiguration(commandName: Kind.name, abstract: Kind.abstract)
        }

        @OptionGroup public var global: GlobalOptions

        public init() {}

        public var subject: String {
            Kind.name
        }
    }

    public struct List: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "Print every setting whose editor ID starts with a prefix."
        )
        @OptionGroup public var global: GlobalOptions
        @Argument(help: ArgumentHelp(
            "The editor ID prefix. Default: every setting.",
            valueName: "prefix"
        ))
        public var prefix = ""

        public init() {}
    }
}

public protocol GMSTSubjectKind: Sendable {
    static var name: String { get }
    static var abstract: String { get }
}

public enum MovementSubject: GMSTSubjectKind {
    public static let name = "movement"
    public static let abstract = "The settings player and actor movement reads."
}

public enum CombatSubject: GMSTSubjectKind {
    public static let name = "combat"
    public static let abstract = "The settings the combat rules read."
}

public enum ArcherySubject: GMSTSubjectKind {
    public static let name = "archery"
    public static let abstract = "The settings arrow flight and bow draw read."
}

public enum DetectionSubject: GMSTSubjectKind {
    public static let name = "detection"
    public static let abstract = "The settings stealth detection reads."
}
