// `install`: the game folder check the launcher shows.

import ArgumentParser

public struct InstallArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Check the game folder: version, DLC, counts, and install problems.",
        discussion: "Reads file names and headers only. Exits 1 when the check finds a problem."
    )
    @OptionGroup public var global: GlobalOptions

    public init() {}
}
