// `swf`: the Scaleform movie parse, render, and ActionScript sweeps.

import ArgumentParser

/// `--movie`: only the movies whose path contains this text.
public struct MovieFilterOption: ParsableArguments, Sendable {
    @Option(
        name: .customLong("movie"), parsing: .unconditional,
        help: ArgumentHelp("Only movies whose path contains this text.", valueName: "text")
    )
    public var text: String?

    public init() {}
}

public struct SWFArguments: ParsableCommand, Sendable {
    public static let configuration = CommandConfiguration(
        commandName: "swf",
        abstract: "Parse, render, and run the interface movies.",
        discussion: "To drive one vanilla menu through its bridge, use the menu command.",
        subcommands: [
            Show.self, Sweep.self, RenderSweep.self, ActionSweep.self, ActionList.self,
            ActionRun.self, MovieProbe.self
        ]
    )

    public init() {}

    public struct Sweep: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "sweep",
            abstract: "Parse every interface movie; tally tags, shapes, fonts, and frame 1."
        )
        @OptionGroup public var global: GlobalOptions

        public init() {}
    }

    public struct Show: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "show",
            abstract: "Parse one movie; print its header and tag list."
        )
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var asset: AssetPathArgument

        public init() {}
    }

    public struct RenderSweep: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "render-sweep",
            abstract: "Render every movie's frame 1 offscreen; report draws and changed pixels.",
            discussion: "--out writes one PNG per movie. Use a .logs/ path: the frames "
                + "embed game art."
        )
        @OptionGroup public var global: GlobalOptions
        @Option(parsing: .unconditional, help: ArgumentHelp("The image size.", valueName: "WxH"))
        public var size = PixelSize.defaultView
        @Option(
            parsing: .unconditional,
            help: ArgumentHelp("Write one PNG per movie here.", valueName: "dir")
        )
        public var out: String?
        @OptionGroup public var movie: MovieFilterOption

        public init() {}
    }

    public struct ActionSweep: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "action-sweep",
            abstract: "Decode every movie's actions; tally opcodes and the API name surface."
        )
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var movie: MovieFilterOption
        @Option(parsing: .unconditional, help: ArgumentHelp("API names to print.", valueName: "n"))
        public var limit = 120

        public init() {}

        public func validate() throws {
            try OptionCheck.atLeast(limit, 1, "--limit")
        }
    }

    public struct ActionList: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "action-list",
            abstract: "Print one movie's action records with names resolved."
        )
        @OptionGroup public var global: GlobalOptions
        @Option(
            parsing: .unconditional,
            help: ArgumentHelp("The movie whose path contains this text.", valueName: "text")
        )
        public var movie: String

        public init() {}
    }

    public struct ActionRun: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "action-run",
            abstract: "Bring one movie up through the AS2 runtime, tick it, and report.",
            discussion: "Prints faults, unresolved placements, the missing-API tally, "
                + "classes, GameDelegate callbacks, the invoke log, and the display tree."
        )
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var movie: MovieFilterOption
        @Option(parsing: .unconditional, help: ArgumentHelp("Frames to run.", valueName: "n"))
        public var ticks = 10
        @Option(
            parsing: .unconditional,
            help: ArgumentHelp("Missing API names to print.", valueName: "n")
        )
        public var limit = 40
        @Option(
            parsing: .unconditional,
            help: ArgumentHelp("Display tree levels to print.", valueName: "n")
        )
        public var treeDepth = 4
        @Option(
            parsing: .unconditional,
            help: ArgumentHelp("Callbacks to invoke first.", valueName: "names")
        )
        public var call: String?
        @Option(
            parsing: .unconditional,
            help: ArgumentHelp("Print one node's own AS2 properties.", valueName: "paths")
        )
        public var dump: String?
        @Option(
            parsing: .unconditional,
            help: ArgumentHelp("Print one class's members.", valueName: "class")
        )
        public var dumpClass: String?
        @Option(
            parsing: .unconditional,
            help: ArgumentHelp("Print one class's prototype members.", valueName: "class")
        )
        public var dumpProto: String?

        public init() {}

        public func validate() throws {
            try OptionCheck.atLeast(ticks, 1, "--ticks")
            try OptionCheck.atLeast(limit, 1, "--limit")
            try OptionCheck.atLeast(treeDepth, 1, "--tree-depth")
        }
    }
}
