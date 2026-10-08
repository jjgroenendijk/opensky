// How Papyrus compares names. Script, state, property, and variable names are
// case-insensitive, so every stored name is folded to one form.

/// The folded form of a Papyrus name.
nonisolated public enum PapyrusName {
    /// `value` folded for comparison and storage. A name already folded comes back
    /// as is, so the common lowercase ASCII name allocates nothing.
    public static func key(_ value: String) -> String {
        for byte in value.utf8 where byte >= 0x80 || isUppercaseASCII(byte) {
            return value.lowercased()
        }
        return value
    }

    /// Whether two names fold to the same key. ASCII names compare byte by byte
    /// without building either key.
    public static func matches(_ left: String, _ right: String) -> Bool {
        let lhs = left.utf8
        let rhs = right.utf8
        guard lhs.count == rhs.count else {
            return !(isASCII(lhs) && isASCII(rhs)) && key(left) == key(right)
        }
        for (first, second) in zip(lhs, rhs) where first != second {
            guard first < 0x80, second < 0x80 else { return key(left) == key(right) }
            guard asciiFolded(first) == asciiFolded(second) else { return false }
        }
        return true
    }

    /// Plain comparisons, not ranges or closures: Debug builds do not inline those.
    private static func isUppercaseASCII(_ byte: UInt8) -> Bool {
        byte >= 0x41 && byte <= 0x5A
    }

    private static func asciiFolded(_ byte: UInt8) -> UInt8 {
        isUppercaseASCII(byte) ? byte | 0x20 : byte
    }

    private static func isASCII(_ bytes: String.UTF8View) -> Bool {
        for byte in bytes where byte >= 0x80 {
            return false
        }
        return true
    }
}
