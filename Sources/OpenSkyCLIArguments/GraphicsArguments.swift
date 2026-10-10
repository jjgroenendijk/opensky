// `graphics status|preset`: the Graphics page's preset from the command line.

import ArgumentParser

public struct GraphicsArguments: ParsableCommand, Sendable {
    public static let configuration = CommandConfiguration(
        commandName: "graphics",
        abstract: "Show or set the graphics preset in the player settings file.",
        subcommands: [Status.self, Preset.self]
    )

    public init() {}

    public struct Status: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Print the current preset and every base game option with its value."
        )
        @OptionGroup public var global: GlobalOptions

        public init() {}
    }

    public struct Preset: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "preset",
            abstract: "Set every option from the game's Low, Medium, High, or Ultra preset file."
        )
        @OptionGroup public var global: GlobalOptions
        @Argument(help: ArgumentHelp(valueName: "low|medium|high|ultra"))
        public var name: String

        public init() {}
    }
}
