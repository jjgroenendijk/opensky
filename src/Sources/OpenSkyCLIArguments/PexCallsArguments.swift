public import ArgumentParser

public struct PexCallsArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "pex-calls",
        abstract: "List every call of one Papyrus function across the archived scripts."
    )
    @OptionGroup public var global: GlobalOptions
    @Argument(help: ArgumentHelp(
        "The called function's name, such as SendPlayerToJail, matched in any case.",
        valueName: "function"
    ))
    public var function: String

    public init() {}

    public func validate() throws {
        guard !function.isEmpty else {
            throw ValidationError("The function name must not be empty.")
        }
    }
}
