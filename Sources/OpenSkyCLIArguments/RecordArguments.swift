// The commands that read records and the archive file system without Metal.

import ArgumentParser

/// `--worldspace`, `--x`, and `--y`: the target exterior cell. The CLI checks the numbers,
/// so its error names the option.
public struct GridOptions: ParsableArguments, Sendable {
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Worldspace editor ID.", valueName: "edid")
    )
    public var worldspace: String?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Cell grid X.", valueName: "n")
    )
    public var x: String?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Cell grid Y.", valueName: "n")
    )
    public var y: String?

    public init() {}
}

public struct VFSArguments: ParsableCommand, Sendable {
    public static let configuration = CommandConfiguration(
        commandName: "vfs",
        abstract: "List and extract resources through the engine file system.",
        subcommands: [List.self, Cat.self]
    )

    public init() {}

    public struct List: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "ls",
            abstract: "List archive entries as \"path<TAB>archive\".",
            discussion: "The pattern uses fnmatch wildcards, or matches a substring."
        )
        @OptionGroup public var global: GlobalOptions
        @Argument public var pattern: String?

        public init() {}
    }

    public struct Cat: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "cat",
            abstract: "Extract one resource to a file. Loose files win, as in the engine."
        )
        @OptionGroup public var global: GlobalOptions
        @Option(
            parsing: .unconditional,
            help: ArgumentHelp("The file to write.", valueName: "file")
        )
        public var out: String
        @Argument public var key: String

        public init() {}
    }
}

public struct RecordArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "record",
        abstract: "Dump one Skyrim.esm record: header, decoded view, and fields."
    )
    @OptionGroup public var global: GlobalOptions
    @Argument(help: ArgumentHelp(valueName: "formid-or-editorid"))
    public var token: String

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

public struct ESSArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "ess",
        abstract: "Inspect a Skyrim save read-only, or list the saves in a folder.",
        usage: "openskycli ess <save.ess> [--offline]\nopenskycli ess list <folder>",
        discussion: "The inspection runs the save's import against the load order; "
            + "--offline skips the load order."
    )
    @OptionGroup public var global: GlobalOptions
    @Argument(help: ArgumentHelp("A .ess file, or list.", valueName: "save.ess"))
    public var target: String
    @Argument(help: ArgumentHelp("The folder that list reads.", valueName: "folder"))
    public var folder: String?
    @Flag(help: "Skip the load order.")
    public var offline = false

    public init() {}
}

public struct GMSTArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "gmst",
        abstract: "Print resolved game settings with the plugin each came from.",
        discussion: "Subjects: movement, combat, archery, detection, and list. "
            + "list prints every setting whose editor ID starts with --prefix."
    )
    @OptionGroup public var global: GlobalOptions
    @Argument(help: ArgumentHelp(valueName: "movement|combat|archery|detection|list"))
    public var subject: String
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("The editor ID prefix for list.", valueName: "s")
    )
    public var prefix = ""

    public init() {}
}

public struct ArcheryArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "archery",
        abstract: "Walk the AMMO to PROJ flight chain, one row per arrow."
    )
    @OptionGroup public var global: GlobalOptions
    @Flag(help: "Add the PROJ-wide distribution that settles how gravity is read.")
    public var census = false
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Only arrows whose editor ID contains this.", valueName: "substring")
    )
    public var ammo: String?

    public init() {}
}

public struct FootstepArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "footstep",
        abstract: "Walk the footstep chain: per gait, each FSTP tag, IPCT, and sound file."
    )
    @OptionGroup public var global: GlobalOptions
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("The footstep set. Default: DefaultFootstepSet.", valueName: "edid")
    )
    public var set: String?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Read the set off this ARMA's SNDD.", valueName: "formid-or-edid")
    )
    public var armature: String?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("The MATT surface under the foot.", valueName: "edid-or-formid")
    )
    public var material: String?

    public init() {}
}

public struct EffectsArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "effects",
        abstract: "Census the IMAD, IMGS, SPGD, SOPM, and REVB records, or sample one IMAD.",
        usage: "openskycli effects census\nopenskycli effects imad <edid> [--at <seconds>]"
    )
    @OptionGroup public var global: GlobalOptions
    @Argument(help: ArgumentHelp(valueName: "census|imad"))
    public var mode: String
    @Argument(help: ArgumentHelp("The IMAD editor ID for imad.", valueName: "edid"))
    public var editorID: String?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("The time to sample the IMAD at.", valueName: "seconds")
    )
    public var at: Float = 0

    public init() {}
}
