// `reference`: the Windows game under Wine, run beside OpenSky to compare
// the two (docs/tools/reference-game.md). Writes go to the reference prefix and `.logs/`.

import ArgumentParser

/// The reference window size; the OpenSky capture renders at the same size.
public struct ReferenceWindowOptions: ParsableArguments, Sendable {
    @Option(parsing: .unconditional, help: "Window width in pixels. Default: 1280.")
    public var width = 1280
    @Option(parsing: .unconditional, help: "Window height in pixels. Default: 720.")
    public var height = 720

    public init() {}

    public func validate() throws {
        guard (320 ... 7680).contains(width), (240 ... 4320).contains(height) else {
            throw ValidationError("--width must be 320 to 7680 and --height 240 to 4320")
        }
    }
}

/// What the generated console batch file toggles.
public struct ReferenceBatchOptions: ParsableArguments, Sendable {
    @Flag(
        name: .customLong("hide-menus"), inversion: .prefixedNo,
        help: "Add tm, which hides the HUD. It toggles, so a second bat run shows it again."
    )
    public var hideMenus = true
    @Flag(help: "Add tfc 1, which freezes the world. It toggles like tm.")
    public var freeze = false

    public init() {}
}

public struct ReferenceArguments: ParsableCommand, Sendable {
    public static let configuration = CommandConfiguration(
        commandName: "reference",
        abstract: "Run the Windows game under Wine and compare it with OpenSky.",
        subcommands: [
            Status.self, Check.self, Launch.self, ExportView.self, Capture.self, State.self,
            Send.self, Sync.self, Follow.self, Load.self, Answer.self
        ]
    )

    public init() {}

    public struct Status: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Print the reference prefix, its Wine, and what the prefix still lacks."
        )
        @OptionGroup public var global: GlobalOptions

        public init() {}
    }

    public struct Check: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "check",
            abstract: "Compare the Steam build and the master files of both installs."
        )
        @OptionGroup public var global: GlobalOptions

        public init() {}
    }

    public struct Launch: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "launch",
            abstract: "Start Windows Steam and the game in the reference prefix."
        )
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var window: ReferenceWindowOptions
        @Option(
            parsing: .unconditional,
            help: "Seconds to wait for a Steam this command started. Default: 30."
        )
        public var steamWait = 30
        @Option(help: "The game's own graphics preset. Low leaves the GPU to OpenSky too.")
        public var preset: GraphicsPresetName = .low

        public init() {}

        public func validate() throws {
            guard (0 ... 600).contains(steamWait) else {
                throw ValidationError("--steam-wait must be 0 to 600 seconds")
            }
        }
    }

    public struct ExportView: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "export-view",
            abstract: "Write the running OpenSky view as a batch file the reference game runs.",
            discussion: "Then type 'bat opensky' in the reference game's console."
        )
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var game: GameOptions
        @OptionGroup public var batch: ReferenceBatchOptions

        public init() {}
    }

    public struct Capture: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "capture",
            abstract: "Capture both games, then write the pair, their difference, and a report.",
            discussion: "Writes .logs/reference/<UTC time>/. Run it after 'bat opensky'."
        )
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var game: GameOptions
        @OptionGroup public var window: ReferenceWindowOptions
        @OptionGroup public var batch: ReferenceBatchOptions

        public init() {}
    }
}
