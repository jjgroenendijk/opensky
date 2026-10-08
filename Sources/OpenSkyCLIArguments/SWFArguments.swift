// `swf`: the Scaleform movie sweeps and the menu movie drivers.

import ArgumentParser

public struct SWFArguments: ParsableCommand, Sendable {
    public static let configuration = CommandConfiguration(
        commandName: "swf",
        abstract: "Parse, render, and run the interface movies.",
        subcommands: [
            Sweep.self, RenderSweep.self, ActionSweep.self, ActionList.self, ActionRun.self,
            Info.self, InventoryMenu.self, QuestJournal.self, ContainerMenu.self,
            SystemMenu.self, MovieProbe.self, DialogueMenu.self
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

    public struct Info: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "info",
            abstract: "Parse one movie; print its header and tag list."
        )
        @OptionGroup public var global: GlobalOptions
        @Argument public var key: String

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
        @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "WxH"))
        public var size: String?
        @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "dir"))
        public var out: String?
        @Option(
            parsing: .unconditional,
            help: ArgumentHelp("Only movies whose path contains this.", valueName: "substring")
        )
        public var movie: String?

        public init() {}
    }

    public struct ActionSweep: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "action-sweep",
            abstract: "Decode every movie's actions; tally opcodes and the API name surface."
        )
        @OptionGroup public var global: GlobalOptions
        @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "substring"))
        public var movie: String?
        @Option(
            parsing: .unconditional,
            help: ArgumentHelp("Printed API names. Default: 120.", valueName: "n")
        )
        public var limit: String?

        public init() {}
    }

    public struct ActionList: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "action-list",
            abstract: "Print one movie's action records with names resolved."
        )
        @OptionGroup public var global: GlobalOptions
        @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "substring"))
        public var movie = ""

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
        @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "substring"))
        public var movie: String?
        @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "n"))
        public var ticks: String?
        @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "n"))
        public var limit: String?
        @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "n"))
        public var treeDepth: String?
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
        @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "class"))
        public var dumpClass: String?
        @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "class"))
        public var dumpProto: String?

        public init() {}
    }
}
