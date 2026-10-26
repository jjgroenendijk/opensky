// The `SkyrimPrefs.ini` values the reference game needs under Wine: a borderless window
// of a fixed size, so its capture matches OpenSky's pixel for pixel, that keeps drawing
// while OpenSky is in front.

import Foundation

/// Where the reference window sits on screen, in Wine's top-left screen points.
nonisolated public struct ReferenceWindowFrame: Equatable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

nonisolated public enum ReferencePrefsIni {
    public static let section = "Display"

    /// Wine ignores `iLocation X` and `Y`; the app moves the window once it is up.
    public static func displayValues(_ frame: ReferenceWindowFrame) -> [ReferenceIniValue] {
        [
            ReferenceIniValue("bBorderless", "1"), ReferenceIniValue("bFull Screen", "0"),
            ReferenceIniValue("iSize W", String(frame.width)),
            ReferenceIniValue("iSize H", String(frame.height))
        ]
    }

    /// `bAlwaysActive` keeps the game drawing and reading keys while another app is in
    /// front; without it the game pauses and drops typed console keys.
    public static let alwaysActive = ReferenceIniValue("bAlwaysActive", "1")

    public static func apply(to text: String, frame: ReferenceWindowFrame) -> String {
        let display = ReferenceIni.set(displayValues(frame), in: section, of: text)
        return ReferenceIni.set([alwaysActive], in: "General", of: display)
    }

    /// Sets every key a preset file such as `Low.ini` names, and keeps the rest.
    public static func apply(preset: String, to text: String) -> String {
        ReferenceIni.sections(of: preset).reduce(text) { result, section in
            ReferenceIni.set(section.values, in: section.name, of: result)
        }
    }
}

nonisolated public struct ReferenceIniValue: Equatable, Sendable {
    public var key: String
    /// `nil` removes the key.
    public var value: String?

    public init(_ key: String, _ value: String?) {
        self.key = key
        self.value = value
    }
}

nonisolated public enum ReferenceIni {
    /// Sets each key in `section`, matching names without case as the game does, and keeps
    /// every other line. A missing key or section is added. Line ends become CRLF.
    public static func set(
        _ values: [ReferenceIniValue], in section: String, of text: String
    ) -> String {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        if lines.last?.isEmpty == true {
            lines.removeLast()
        }
        var pending = values
        var range = sectionRange(section, in: lines)
        if range == nil {
            guard values.contains(where: { $0.value != nil }) else { return joined(lines) }
            lines.append("[\(section)]")
            range = lines.count ..< lines.count
        }
        guard let range else { return text }
        var removed: [Int] = []
        for index in range {
            guard let equals = lines[index].firstIndex(of: "=") else { continue }
            let key = lines[index][..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            guard let match = pending.firstIndex(where: { $0.key.lowercased() == key })
            else { continue }
            if let value = pending[match].value {
                lines[index] = "\(pending[match].key)=\(value)"
            } else {
                removed.append(index)
            }
            pending.remove(at: match)
        }
        let added = pending.compactMap { item in item.value.map { "\(item.key)=\($0)" } }
        lines.insert(contentsOf: added, at: range.upperBound)
        for index in removed.reversed() {
            lines.remove(at: index)
        }
        return joined(lines)
    }

    /// Each section's `key=value` lines in file order; comments and blank lines are skipped.
    public static func sections(of text: String) -> [(name: String, values: [ReferenceIniValue])] {
        var sections: [(name: String, values: [ReferenceIniValue])] = []
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("["), line.hasSuffix("]") {
                sections.append((String(line.dropFirst().dropLast()), []))
            } else if
                !line.hasPrefix(";"), let equals = line.firstIndex(of: "="),
                !sections.isEmpty
            {
                let key = line[..<equals].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
                sections[sections.count - 1].values.append(ReferenceIniValue(key, value))
            }
        }
        return sections
    }

    private static func joined(_ lines: [String]) -> String {
        lines.isEmpty ? "" : lines.joined(separator: "\r\n") + "\r\n"
    }

    /// The lines after `[section]` up to the next section header, without trailing blanks.
    static func sectionRange(_ section: String, in lines: [String]) -> Range<Int>? {
        let header = "[\(section.lowercased())]"
        guard
            let start = lines.firstIndex(where: {
                $0.trimmingCharacters(in: .whitespaces).lowercased() == header
            }) else { return nil }
        let end = lines[(start + 1)...].firstIndex {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("[")
        } ?? lines.count
        var last = end
        while last > start + 1, lines[last - 1].trimmingCharacters(in: .whitespaces).isEmpty {
            last -= 1
        }
        return (start + 1) ..< last
    }
}
