// `openskycli sweep`: headless runs over every quest, fragment, or data rule.

public import ArgumentParser

public struct SweepArguments: ParsableCommand, Sendable {
    public static let configuration = CommandConfiguration(
        commandName: "sweep",
        abstract: "Run every quest, script fragment, or data rule headless and rank what fails.",
        subcommands: [Quests.self, Fragments.self, Rules.self]
    )

    public init() {}

    /// The options every sweep shares.
    public struct Report: ParsableArguments, Sendable {
        @Option(
            parsing: .unconditional,
            help: ArgumentHelp(
                "Write report.txt and fallbacks.tsv to this directory instead of "
                    + ".logs/sweep-<kind>/<UTC time>/.",
                valueName: "directory"
            )
        )
        public var out: String?
        @Option(
            parsing: .unconditional,
            help: ArgumentHelp(
                "Problems printed. Default: all. The file keeps all.",
                valueName: "n"
            )
        )
        public var limit: Int?
        @Option(
            parsing: .unconditional,
            help: ArgumentHelp("Subjects named per problem.", valueName: "n")
        )
        public var examples = 3

        public init() {}

        public func validate() throws {
            try OptionCheck.atLeast(limit, 1, "--limit")
            try OptionCheck.atLeast(examples, 1, "--examples")
        }
    }

    public struct Quests: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "quests",
            abstract: "Start every start-game-enabled and story-manager quest and rank what "
                + "stops them."
        )
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var report: Report

        public init() {}
    }

    public struct Fragments: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "fragments",
            abstract: "Run every quest stage, topic info, scene, and package fragment and "
                + "rank the problems they meet."
        )
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var report: Report

        public init() {}
    }

    public struct Rules: CLICommandArguments {
        public static let configuration = CommandConfiguration(
            commandName: "rules",
            abstract: "Check the rules vanilla data implies and list the violations per rule."
        )
        @OptionGroup public var global: GlobalOptions
        @OptionGroup public var report: Report

        public init() {}
    }
}
