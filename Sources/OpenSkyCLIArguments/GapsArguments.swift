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
        help: ArgumentHelp("Comma-separated sections to run. Default: all.", valueName: "list")
    )
    public var only: String?
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
        let asked = Set(only.lowercased().split(separator: ",").map(String.init))
        return Self.sectionKeys.filter(asked.contains)
    }

    public func validate() throws {
        if let only {
            let unknown = only.lowercased().split(separator: ",").map(String.init)
                .filter { !Self.sectionKeys.contains($0) }
            guard unknown.isEmpty else {
                throw ValidationError("unknown section: \(unknown.joined(separator: ", "))")
            }
        }
        if let limit, limit < 1 {
            throw ValidationError("--limit needs a positive integer")
        }
    }
}
