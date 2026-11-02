// How much of a big record the text dumps print. The preview GUI pane keeps the caps;
// `openskycli record show` writes everything to a file.

nonisolated public struct DumpLimits: Equatable, Sendable {
    /// Lines of the decoded view.
    public var lines: Int
    /// Elements printed per decoded collection.
    public var collection: Int
    /// Raw fields, list entries, ranks, and relations.
    public var fields: Int
    /// Nesting of the decoded view; it only stops runaway reflection.
    public var depth: Int

    public static let preview = DumpLimits(lines: 400, collection: 24, fields: 64, depth: 8)
    public static let complete = DumpLimits(
        lines: .max, collection: .max, fields: .max, depth: 32
    )

    /// The limits the dumps on this task use.
    @TaskLocal public static var current = DumpLimits.preview

    public init(lines: Int, collection: Int, fields: Int, depth: Int) {
        self.lines = lines
        self.collection = collection
        self.fields = fields
        self.depth = depth
    }
}
