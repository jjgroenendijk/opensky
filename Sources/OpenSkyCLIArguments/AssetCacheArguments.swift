// `asset-cache` and the cache options the benchmarks share.

import ArgumentParser

/// The cache settings. Each one the user leaves out comes from the app's settings.
public struct AssetCacheSettingsOptions: ParsableArguments, Sendable {
    @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "best|balanced|highest"))
    public var preset: String?
    @Option(parsing: .unconditional, help: ArgumentHelp("The cache folder.", valueName: "dir"))
    public var folder: String?
    @Option(parsing: .unconditional, help: ArgumentHelp("The size limit.", valueName: "n"))
    public var limitGib: String?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Asset kinds, separated by commas.", valueName: "list")
    )
    public var kinds: String?

    public init() {}
}

/// How the benchmarks load assets: through the cache, fast loading, or loose copies.
public struct AssetLoadArguments: ParsableArguments, Sendable {
    @Flag(help: "Load through the asset cache.")
    public var assetCache = false
    @Flag(help: "Drop the files from the page cache first.")
    public var evict = false
    @Flag(help: "Read cached textures with Metal fast resource loading.")
    public var fastLoad = false
    @Flag(help: "Read cached meshes with Metal fast resource loading.")
    public var fastMeshLoad = false
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Read extracted copies here first.", valueName: "dir")
    )
    public var loose: String?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Write the asset paths it read here.", valueName: "file")
    )
    public var recordPaths: String?
    @OptionGroup public var cache: AssetCacheSettingsOptions

    public init() {}
}

/// The options every cache action takes.
public struct AssetCacheActionOptions: ParsableArguments, Sendable {
    @OptionGroup public var settings: AssetCacheSettingsOptions
    @Option(parsing: .unconditional, help: ArgumentHelp("Build threads.", valueName: "n"))
    public var width: String?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Only the files listed here, one per line.", valueName: "file")
    )
    public var paths: String?
    @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "dir"))
    public var out: String?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Sample size per asset kind. Default: 300.", valueName: "n")
    )
    public var perKind: String?

    public init() {}
}

public enum AssetCacheAction: String, Sendable {
    case build, check, clear, status, extract, ioBench = "io-bench", measure
}

/// One `asset-cache` action except `compare`.
public protocol AssetCacheActionArguments: CLICommandArguments {
    static var action: AssetCacheAction { get }
    var options: AssetCacheActionOptions { get }
}

public struct AssetCacheArguments: ParsableCommand, Sendable {
    public static let configuration = CommandConfiguration(
        commandName: "asset-cache",
        abstract: "Build, check, clear, show, or measure the asset cache.",
        subcommands: [
            Build.self, Check.self, Clear.self, Status.self, Extract.self, IOBench.self,
            Measure.self, Compare.self
        ]
    )

    public init() {}

    public struct Build: AssetCacheActionArguments {
        public static let configuration = CommandConfiguration(
            commandName: "build",
            abstract: "Build the cache."
        )
        public static let action = AssetCacheAction.build
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var options: AssetCacheActionOptions

        public init() {}
    }

    public struct Check: AssetCacheActionArguments {
        public static let configuration = CommandConfiguration(
            commandName: "check",
            abstract: "Check every cache entry against its source."
        )
        public static let action = AssetCacheAction.check
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var options: AssetCacheActionOptions

        public init() {}
    }

    public struct Clear: AssetCacheActionArguments {
        public static let configuration = CommandConfiguration(
            commandName: "clear",
            abstract: "Delete the cache."
        )
        public static let action = AssetCacheAction.clear
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var options: AssetCacheActionOptions

        public init() {}
    }

    public struct Status: AssetCacheActionArguments {
        public static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Show the cache settings and contents."
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
            abstract: "Per asset kind, load a sample from the archives and the cache."
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
        @Argument(help: ArgumentHelp(valueName: "reference.png"))
        public var reference: String
        @Argument(help: ArgumentHelp(valueName: "candidate.png"))
        public var candidate: String

        public init() {}
    }
}
