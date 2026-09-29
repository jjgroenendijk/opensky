// How Papyrus compares names. Script, state, property, and variable names are
// case-insensitive, so every stored name is folded to one form.

/// The folded form of a Papyrus name.
nonisolated public enum PapyrusName {
    /// `value` folded for comparison and storage.
    public static func key(_ value: String) -> String {
        value.lowercased()
    }
}
