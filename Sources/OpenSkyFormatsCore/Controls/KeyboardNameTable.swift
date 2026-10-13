// interface\controls\pc\keyboard_english.txt: the name of each DirectInput key, such as
// `L-Ctrl` or `Slash`. Menus use the name as the symbol of the key's button art.
// Layout: docs/formats/controlmap.md.

import Foundation

nonisolated public struct KeyboardNameTable: Equatable, Sendable {
    /// The VFS key of the vanilla file.
    public static let path = "interface\\controls\\pc\\keyboard_english.txt"

    /// Scan code to name. A code listed twice keeps its first name.
    public let names: [UInt32: String]

    public init(names: [UInt32: String]) {
        self.names = names
    }

    /// Lines are tab separated: name, hex scan code, and an optional Flash key code.
    /// `//` starts a comment. A line without a hex code is skipped.
    public init(data: Data) throws(ControlMapError) {
        guard
            let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
        else { throw .notText }
        var names: [UInt32: String] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.components(separatedBy: "//")[0]
            let fields = line.split(separator: "\t").map {
                $0.trimmingCharacters(in: .whitespaces)
            }.filter { !$0.isEmpty }
            guard
                fields.count >= 2, fields[1].lowercased().hasPrefix("0x"),
                let code = UInt32(fields[1].dropFirst(2), radix: 16),
                names[code] == nil
            else { continue }
            names[code] = fields[0]
        }
        self.names = names
    }

    public func name(_ scanCode: UInt32) -> String? {
        names[scanCode]
    }
}
