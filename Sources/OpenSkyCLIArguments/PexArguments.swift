import ArgumentParser

public struct PexArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "pex",
        abstract: "Disassemble a compiled Papyrus script: members, states, and instructions."
    )
    @OptionGroup public var global: GlobalOptions
    @Argument(help: ArgumentHelp(
        "A script name, such as DLC1VampireTurnScript, or its archive path.",
        valueName: "script"
    ))
    public var script: String
    @Option(
        parsing: .unconditional,
        help: "Print only the functions of this name, in any case."
    )
    public var function = ""

    public init() {}
}
