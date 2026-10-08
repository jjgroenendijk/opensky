// The commands that inspect one asset file, or sweep every file of a kind.

import ArgumentParser

public struct NIFArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "nif",
        abstract: "Inspect a mesh: container stats and the flattened model."
    )
    @OptionGroup public var global: GlobalOptions
    @Argument public var key: String

    public init() {}
}

public struct DDSArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "dds",
        abstract: "Inspect a texture: header and mip chain."
    )
    @OptionGroup public var global: GlobalOptions
    @Argument public var key: String

    public init() {}
}

public struct HKXArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "hkx",
        abstract: "Inspect a Havok packfile: header, sections, classes, and objects."
    )
    @OptionGroup public var global: GlobalOptions
    @Argument public var key: String

    public init() {}
}

public struct HKTArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "hkt",
        abstract: "Decode a Havok binary tagfile, or every archived one with sweep.",
        usage: "openskycli hkt <key>\nopenskycli hkt sweep"
    )
    @OptionGroup public var global: GlobalOptions
    @Argument(help: ArgumentHelp(valueName: "key|sweep"))
    public var target: String

    public init() {}
}

public struct SkeletonArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "skeleton",
        abstract: "Decode each hkaSkeleton: bone names, parent chain, and roots."
    )
    @OptionGroup public var global: GlobalOptions
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Map the rig onto this NIF's skeleton nodes.", valueName: "nif-key")
    )
    public var nif: String?
    @Argument(help: ArgumentHelp(valueName: "hkx-key"))
    public var key: String

    public init() {}
}

public struct AnimationArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "animation",
        abstract: "Decode spline-compressed tracks and sample every frame of the clip."
    )
    @OptionGroup public var global: GlobalOptions
    @Argument(help: ArgumentHelp(valueName: "hkx-key"))
    public var key: String

    public init() {}
}

public struct AudioArguments: ParsableCommand, Sendable {
    public static let configuration = CommandConfiguration(
        commandName: "audio",
        abstract: "Frame and check the game's .xwm and .fuz audio.",
        subcommands: [Info.self, Sweep.self, VoiceSweep.self, AACCheck.self]
    )

    public init() {}

    public struct Info: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "info",
            abstract: "Frame one .xwm or .fuz file and print its headers. No decode."
        )
        @OptionGroup public var global: GlobalOptions
        @Argument public var key: String

        public init() {}
    }

    public struct Sweep: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "sweep",
            abstract: "Frame and decode every .xwm the archives provide."
        )
        @OptionGroup public var global: GlobalOptions

        public init() {}
    }

    public struct VoiceSweep: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "voice-sweep",
            abstract: "Derive every voice file name from the records and frame each .fuz."
        )
        @OptionGroup public var global: GlobalOptions
        @Option(
            parsing: .unconditional,
            help: ArgumentHelp("Frame at most this many files.", valueName: "n")
        )
        public var limit: String?
        @Flag(help: "Stop after the naming check.")
        public var namesOnly = false

        public init() {}
    }

    public struct AACCheck: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "aac-check",
            abstract: "Measure AAC distortion per cached sound category; print AAC or ALAC."
        )
        @OptionGroup public var global: GlobalOptions
        @Option(
            parsing: .unconditional,
            help: ArgumentHelp("Sounds per category. Default: 40.", valueName: "n")
        )
        public var perCategory: String?
        @Option(
            parsing: .unconditional,
            help: ArgumentHelp("Write one row per sound here.", valueName: "file")
        )
        public var out: String?

        public init() {}
    }
}
