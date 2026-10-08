// `game`: drives the running app over its agent control socket
// (docs/tools/agent-control.md). Words the CLI does not know pass to the app.

import ArgumentParser

public struct GameOptions: ParsableArguments, Sendable {
    @Flag(help: "Print path: value lines instead of JSON.")
    public var text = false
    @Option(parsing: .unconditional, help: ArgumentHelp("The agent socket.", valueName: "path"))
    public var socket: String?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Seconds a command may wait for its reply.", valueName: "s")
    )
    public var replyTimeout: String?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Record each request and reply here.", valueName: "file")
    )
    public var record: String?

    public init() {}
}

public struct GameArguments: ParsableCommand, Sendable {
    public static let configuration = CommandConfiguration(
        commandName: "game",
        abstract: "Drive the running app over its agent control socket.",
        discussion: "Each call prints one JSON object. Other commands go to the app: "
            + "status, quit, screenshot, input, time, state, debug, and events. "
            + "See docs/tools/agent-control.md.",
        subcommands: [Launch.self, Attach.self, Run.self, Send.self],
        defaultSubcommand: Send.self
    )

    public init() {}

    public struct Launch: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "launch",
            abstract: "Start the app, or attach to the running one, and wait for the world."
        )
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var game: GameOptions
        @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "play|developer"))
        public var mode = "play"
        @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "path"))
        public var app: String?
        @Option(
            parsing: .unconditional,
            help: ArgumentHelp("Seconds to wait for the world. Default: 180.", valueName: "s")
        )
        public var wait: Double?
        @Flag(help: "Open the title screen instead of the world.")
        public var title = false

        public init() {}
    }

    public struct Attach: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "attach",
            abstract: "Connect to the running app and print its hello."
        )
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var game: GameOptions

        public init() {}
    }

    public struct Run: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "run",
            abstract: "Run a JSON Lines script of requests and expectations."
        )
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var game: GameOptions
        @Argument(help: ArgumentHelp(valueName: "script.jsonl"))
        public var script: String

        public init() {}
    }

    /// Every other command: the words go to the app's own command parser.
    public struct Send: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "send",
            abstract: "Send one command to the app.",
            shouldDisplay: false
        )
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var game: GameOptions
        @Argument(parsing: .allUnrecognized)
        public var words: [String] = []

        public init() {}
    }
}
