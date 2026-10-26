// The commands that read the archive file system: one asset file, or every file of a kind.

import ArgumentParser

/// `<path>`: one file in the engine file system. Loose files win over archives.
public struct AssetPathArgument: ParsableArguments, Sendable {
    @Argument(help: ArgumentHelp(
        "An archive path, such as meshes\\clutter\\bucket01.nif. Any case, either slash.",
        valueName: "path"
    ))
    public var path: String

    public init() {}
}

public struct VFSArguments: ParsableCommand, Sendable {
    public static let configuration = CommandConfiguration(
        commandName: "vfs",
        abstract: "List and extract files through the engine file system.",
        subcommands: [List.self, Cat.self]
    )

    public init() {}

    public struct List: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "ls",
            abstract: "List archive entries as \"path<TAB>archive\"."
        )
        @OptionGroup public var global: GlobalOptions
        @Argument(help: ArgumentHelp(
            "An fnmatch wildcard or a substring. Default: every entry.", valueName: "pattern"
        ))
        public var pattern: String?
        @Option(
            parsing: .unconditional,
            help: ArgumentHelp(
                "Keep only entries whose bytes hold this text, such as a NIF block type.",
                valueName: "text"
            )
        )
        public var containing: String?

        public init() {}
    }

    public struct Cat: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "cat",
            abstract: "Extract one file. Loose files win, as in the engine."
        )
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var asset: AssetPathArgument
        @Option(
            parsing: .unconditional,
            help: ArgumentHelp("The file to write.", valueName: "file")
        )
        public var out: String

        public init() {}
    }
}

public struct NIFArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "nif",
        abstract: "Inspect a mesh: container stats and the flattened model."
    )
    @OptionGroup public var global: GlobalOptions
    @OptionGroup public var asset: AssetPathArgument
    @Flag(help: "Also print the node tree, unlit shapes, and controller sequences.")
    public var sequences = false
    @Flag(help: "Also print the node controllers that play on their own clock, and bone LOD.")
    public var controllers = false

    public init() {}
}

public struct DDSArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "dds",
        abstract: "Inspect a texture: header and mip chain."
    )
    @OptionGroup public var global: GlobalOptions
    @OptionGroup public var asset: AssetPathArgument

    public init() {}
}

public struct HKXArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "hkx",
        abstract: "Inspect a Havok packfile: header, sections, classes, and objects."
    )
    @OptionGroup public var global: GlobalOptions
    @OptionGroup public var asset: AssetPathArgument
    @Flag(help: "List every blender: flags, bound blend parameter, and each child.")
    public var blenders = false
    @Option(
        parsing: .unconditionalSingleValue,
        help: "Step the actor graph, raise this event, print each state reached. Repeatable."
    )
    public var raise: [String] = []
    @Option(
        name: .customLong("set"), parsing: .unconditionalSingleValue,
        help: "With --raise: hold a variable, as name=value. Repeatable."
    )
    public var variables: [String] = []

    public init() {}

    public mutating func validate() throws {
        for entry in variables where entry.split(separator: "=").count != 2
            || Float(entry.split(separator: "=").last ?? "") == nil
        {
            throw ValidationError("--set takes name=value with a number, got \(entry)")
        }
        if !variables.isEmpty, raise.isEmpty {
            throw ValidationError("--set needs --raise")
        }
    }
}

public struct HKTArguments: ParsableCommand, Sendable {
    public static let configuration = CommandConfiguration(
        commandName: "hkt",
        abstract: "Decode Havok binary tagfiles.",
        subcommands: [Show.self, Sweep.self]
    )

    public init() {}

    public struct Show: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "show",
            abstract: "Decode one tagfile: class versions, objects, and skeleton bones."
        )
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var asset: AssetPathArgument

        public init() {}
    }

    public struct Sweep: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "sweep",
            abstract: "Decode every archived .hkt and count the results."
        )
        @OptionGroup public var global: GlobalOptions

        public init() {}
    }
}

public struct SkeletonArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "skeleton",
        abstract: "Decode each hkaSkeleton: bone names, parent chain, and roots."
    )
    @OptionGroup public var global: GlobalOptions
    @OptionGroup public var asset: AssetPathArgument
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Map the rig onto this NIF's skeleton nodes.", valueName: "nif-path")
    )
    public var nif: String?
    @Flag(help: "List every bone, not only the first 12.")
    public var all = false

    public init() {}
}

public struct AnimationArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "animation",
        abstract: "Decode spline-compressed tracks and sample every frame of the clip."
    )
    @OptionGroup public var global: GlobalOptions
    @OptionGroup public var asset: AssetPathArgument

    public init() {}
}

public struct AudioArguments: ParsableCommand, Sendable {
    public static let configuration = CommandConfiguration(
        commandName: "audio",
        abstract: "Frame and check the game's .xwm and .fuz audio.",
        subcommands: [Show.self, Sweep.self, VoiceSweep.self, AACCheck.self]
    )

    public init() {}

    public struct Show: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "show",
            abstract: "Frame one .xwm or .fuz file and print its headers. No decode."
        )
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var asset: AssetPathArgument

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
        public var limit: Int?
        @Flag(help: "Stop after the naming check.")
        public var namesOnly = false

        public init() {}

        public func validate() throws {
            try OptionCheck.atLeast(limit, 1, "--limit")
        }
    }

    public struct AACCheck: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "aac-check",
            abstract: "Measure AAC distortion per cached sound category; print AAC or ALAC."
        )
        @OptionGroup public var global: GlobalOptions
        @Option(parsing: .unconditional, help: ArgumentHelp("Sounds per category.", valueName: "n"))
        public var perCategory = 40
        @Option(
            parsing: .unconditional,
            help: ArgumentHelp("Write one row per sound here.", valueName: "file")
        )
        public var out: String?

        public init() {}

        public func validate() throws {
            try OptionCheck.atLeast(perCategory, 1, "--per-category")
        }
    }
}
