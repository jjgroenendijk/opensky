// `openskycli gaps`: what the install asks for that the engine does not do yet.

import ArgumentParser

public struct GapsArguments: CLICommandArguments {
    public static let sectionKeys = [
        "papyrus", "events", "conditions", "records", "settings", "magic", "perks", "packages",
        "behavior", "animations", "meshes", "textures", "audio", "swf"
    ]

    public static let configuration = CommandConfiguration(
        commandName: "gaps",
        abstract: "Rank what the game data uses and the engine does not implement yet.",
        discussion: "Sections: \(sectionKeys.joined(separator: ", ")). Each prints how much "
            + "is done and what is left, ranked by how often the data uses it."
    )
    @OptionGroup public var global: GlobalOptions
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Sections to run, comma-separated. Default: all.", valueName: "list")
    )
    public var only: CommaList?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Rows printed per section. Default: all.", valueName: "n")
    )
    public var limit: Int?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Also write the summary as a Markdown table here.", valueName: "path")
    )
    public var summaryOut: String?

    public init() {}

    /// The sections to run, in the order `sectionKeys` lists them.
    public var sections: [String] {
        guard let only else { return Self.sectionKeys }
        let asked = Set(only.items.map { $0.lowercased() })
        return Self.sectionKeys.filter(asked.contains)
    }

    public func validate() throws {
        if let only {
            let unknown = only.items.map { $0.lowercased() }
                .filter { !Self.sectionKeys.contains($0) }
            guard unknown.isEmpty else {
                throw ValidationError("unknown section: \(unknown.joined(separator: ", "))")
            }
        }
        try OptionCheck.atLeast(limit, 1, "--limit")
    }
}
