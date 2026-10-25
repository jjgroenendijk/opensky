// `asset-optimisation`: build, check, and measure the optimised files.

import ArgumentParser

/// The optimisation settings. Each one the user leaves out comes from the app's settings.
public struct AssetCacheSettingsOptions: ParsableArguments, Sendable {
    @Option(parsing: .unconditional, help: ArgumentHelp("The texture quality to build."))
    public var textureQuality: TextureQualityName?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Drop texture levels larger than this side.", valueName: "pixels")
    )
    public var maxTextureSide: Int?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("The optimised files folder.", valueName: "dir")
    )
    public var folder: String?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Asset kinds, comma-separated.", valueName: "list")
    )
    public var kinds: CommaList?

    public init() {}

    public func validate() throws {
        try OptionCheck.atLeast(maxTextureSide, 1, "--max-texture-side")
    }
}

/// The options every cache action takes.
public struct AssetCacheActionOptions: ParsableArguments, Sendable {
    @OptionGroup public var settings: AssetCacheSettingsOptions
    @Option(parsing: .unconditional, help: ArgumentHelp("Build threads.", valueName: "n"))
    public var width: Int?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Only the files listed here, one per line.", valueName: "file")
    )
    public var paths: String?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("The folder extract writes the loose copies to.", valueName: "dir")
    )
    public var out: String?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Sample size per asset kind.", valueName: "n")
    )
    public var perKind = 300

    public init() {}

    public func validate() throws {
        try OptionCheck.atLeast(width, 1, "--width")
        try OptionCheck.atLeast(perKind, 1, "--per-kind")
    }
}

public enum AssetCacheAction: String, Sendable {
    case build, check, clear, status, extract, ioBench = "io-bench", measure
}

/// One `asset-optimisation` action except `compare`.
public protocol AssetCacheActionArguments: CLICommandArguments {
    static var action: AssetCacheAction { get }
    var options: AssetCacheActionOptions { get }
}

public struct AssetCacheArguments: ParsableCommand, Sendable {
    public static let configuration = CommandConfiguration(
        commandName: "asset-optimisation",
        abstract: "Convert, check, clear, show, or measure the optimised asset files.",
        subcommands: [
            Build.self, Check.self, Clear.self, Status.self, Extract.self, IOBench.self,
            Measure.self, Compare.self
        ]
    )

    public init() {}

    public struct Build: AssetCacheActionArguments {
        public static let configuration = CommandConfiguration(
            commandName: "build",
            abstract: "Convert the files that wait."
        )
        public static let action = AssetCacheAction.build
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var options: AssetCacheActionOptions

        public init() {}
    }

    public struct Check: AssetCacheActionArguments {
        public static let configuration = CommandConfiguration(
            commandName: "check",
            abstract: "Count the files that are current, stale, or missing."
        )
        public static let action = AssetCacheAction.check
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var options: AssetCacheActionOptions

        public init() {}
    }

    public struct Clear: AssetCacheActionArguments {
        public static let configuration = CommandConfiguration(
            commandName: "clear",
            abstract: "Delete the optimised files."
        )
        public static let action = AssetCacheAction.clear
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var options: AssetCacheActionOptions

        public init() {}
    }

    public struct Status: AssetCacheActionArguments {
        public static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Show the settings and the folder contents."
        )
        public static let action = AssetCacheAction.status
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var options: AssetCacheActionOptions

        public init() {}
    }

    public struct Extract: AssetCacheActionArguments {
        public static let configuration = CommandConfiguration(
            commandName: "extract",
            abstract: "Write loose copies of the --paths files into --out, the baseline."
        )
        public static let action = AssetCacheAction.extract
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var options: AssetCacheActionOptions

        public init() {}
    }

    public struct IOBench: AssetCacheActionArguments {
        public static let configuration = CommandConfiguration(
            commandName: "io-bench",
            abstract: "Load the --paths textures as one batch each way, cold and warm."
        )
        public static let action = AssetCacheAction.ioBench
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var options: AssetCacheActionOptions

        public init() {}
    }

    public struct Measure: AssetCacheActionArguments {
        public static let configuration = CommandConfiguration(
            commandName: "measure",
            abstract: "Per asset kind, load a sample from the archives and the optimised files."
        )
        public static let action = AssetCacheAction.measure
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var options: AssetCacheActionOptions

        public init() {}
    }

    public struct Compare: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "compare",
            abstract: "PSNR and largest channel error of two captures of the same view."
        )
        @OptionGroup public var global: GlobalOptions
        @Argument(help: ArgumentHelp("The capture to compare against.", valueName: "reference.png"))
        public var reference: String
        @Argument(help: ArgumentHelp("The capture to check.", valueName: "candidate.png"))
        public var candidate: String

        public init() {}
    }
}
