// `reference state|send|sync|follow|load`: the Windows game through the OpenSkyBridge
// plugin, with no typed console keys (docs/tools/reference-game.md#the-bridge-plugin).

import ArgumentParser

extension ReferenceArguments {
    public struct State: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "state",
            abstract: "Print the Windows game's state as the bridge reports it."
        )
        @OptionGroup public var global: GlobalOptions

        public init() {}
    }

    public struct Send: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "send",
            abstract: "Run console commands in the Windows game.",
            discussion: "Each argument is one command, such as 'set gamehour to 12'."
        )
        @OptionGroup public var global: GlobalOptions
        @Argument(help: "One console command per argument.")
        public var commands: [String]

        public init() {}

        public func validate() throws {
            guard !commands.isEmpty else { throw ValidationError("give at least one command") }
        }
    }

    public struct Sync: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "sync",
            abstract: "Put the Windows game at the running OpenSky's view.",
            discussion: "The same commands export-view writes, run through the bridge."
        )
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var game: GameOptions
        @OptionGroup public var batch: ReferenceBatchOptions

        public init() {}
    }

    public struct Follow: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "follow",
            abstract: "Put the running OpenSky at the Windows game's view."
        )
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var game: GameOptions

        public init() {}
    }

    public struct Load: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "load",
            abstract: "Load a save in the Windows game from its main menu.",
            discussion: "Give the file name in the prefix's Saves folder; no name loads the newest."
        )
        @OptionGroup public var global: GlobalOptions
        @Argument(help: "The save's file name, with or without .ess.")
        public var save: String?

        public init() {}
    }
}
