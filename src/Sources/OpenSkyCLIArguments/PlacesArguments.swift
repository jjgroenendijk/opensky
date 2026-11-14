// `openskycli places`: the places a new game can start at.

public import ArgumentParser

public struct PlacesArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "places",
        abstract: "List the places a new game can start at: named interiors and map markers.",
        discussion: "Each row is the start value, the name, and where the place is. Give the "
            + "start value to 'game debug newgame --at'."
    )
    @OptionGroup public var global: GlobalOptions
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp(
            "Print only the places that hold every word of this text.", valueName: "text"
        )
    )
    public var search: String?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Rows printed. Default: all.", valueName: "n")
    )
    public var limit: Int?
    @Flag(help: "Print the weather editor IDs in place of the places.")
    public var weathers = false

    public init() {}

    public func validate() throws {
        try OptionCheck.atLeast(limit, 1, "--limit")
    }
}
