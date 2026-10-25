// The commands that walk one game rule's record chain and print what it resolves to.

import ArgumentParser

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
        help: ArgumentHelp("Only arrows whose editor ID contains this.", valueName: "text")
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
        help: ArgumentHelp(
            "Read the set off this ARMA's SNDD: FormID or editor ID.",
            valueName: "id"
        )
    )
    public var armature: String?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("The MATT surface under the foot: FormID or editor ID.", valueName: "id")
    )
    public var material: String?

    public init() {}
}

public struct EffectsArguments: ParsableCommand, Sendable {
    public static let configuration = CommandConfiguration(
        commandName: "effects",
        abstract: "Count the effect records the runtimes read, or sample one IMAD.",
        subcommands: [Census.self, IMAD.self]
    )

    public init() {}

    public struct Census: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "census",
            abstract: "Count the IMAD, IMGS, SPGD, SOPM, REVB, and EXPL records."
        )
        @OptionGroup public var global: GlobalOptions

        public init() {}
    }

    public struct IMAD: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "imad",
            abstract: "Sample one image space modifier at a time."
        )
        @OptionGroup public var global: GlobalOptions
        @Argument(help: ArgumentHelp("The IMAD editor ID.", valueName: "edid"))
        public var editorID: String
        @Option(
            parsing: .unconditional,
            help: ArgumentHelp("The time to sample at.", valueName: "seconds")
        )
        public var at: Float = 0

        public init() {}

        public func validate() throws {
            try OptionCheck.atLeast(at, 0, "--at")
        }
    }
}
