// The `SkyrimPrefs.ini` values the reference game needs under Wine: a borderless
// window of a fixed size, so its capture matches OpenSky's pixel for pixel.

import Foundation

nonisolated public enum ReferencePrefsIni {
    public static let section = "Display"

    public static func displayValues(width: Int, height: Int) -> [(key: String, value: String)] {
        [
            ("bBorderless", "1"), ("bFull Screen", "0"),
            ("iSize W", String(width)), ("iSize H", String(height))
        ]
    }

    /// Sets each key in `[Display]`, matching names without case as the game does, and
    /// keeps every other line. A missing key or section is added. Line ends stay CRLF.
    public static func apply(to text: String, width: Int, height: Int) -> String {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        if lines.last?.isEmpty == true {
            lines.removeLast()
        }
        var pending = displayValues(width: width, height: height)
        var range = sectionRange(in: lines)
        if range == nil {
            lines.append("[\(section)]")
            range = lines.count ..< lines.count
        }
        guard let range else { return text }
        for index in range {
            guard let equals = lines[index].firstIndex(of: "=") else { continue }
            let key = lines[index][..<equals].trimmingCharacters(in: .whitespaces)
            if let match = pending.firstIndex(where: { $0.key.lowercased() == key.lowercased() }) {
                lines[index] = "\(pending[match].key)=\(pending[match].value)"
                pending.remove(at: match)
            }
        }
        lines.insert(contentsOf: pending.map { "\($0.key)=\($0.value)" }, at: range.upperBound)
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// The lines after `[Display]` up to the next section header.
    static func sectionRange(in lines: [String]) -> Range<Int>? {
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
