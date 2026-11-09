/// The clips of the title movie `interface\titles.swf`.
nonisolated public enum TitleSequenceClip {
    public static let names = ["sequence1", "sequence2", "sequence3", "sequence4"]

    /// The clip a script names, matched without case: MQ101 asks for "Sequence1".
    public static func path(for sequence: String) -> String? {
        let name = sequence.lowercased()
        return names.contains(name) ? "_root.\(name)" : nil
    }
}
