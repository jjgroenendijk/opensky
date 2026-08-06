// Reusable Bethesda-style INI parser + typed layered lookup. Files are
// applied low -> high priority; a malformed high-priority typed value is
// ignored so the next valid source (or caller fallback) remains usable.

import Foundation

nonisolated struct INIFile: Equatable {
    private var values: [String: [String: String]] = [:]

    init(data: Data) {
        guard
            var text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252)
        else { return }
        if text.first == "\u{FEFF}" {
            text.removeFirst()
        }

        var section = ""
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix(";"), !line.hasPrefix("#") else {
                continue
            }
            if line.hasPrefix("["), line.hasSuffix("]") {
                section = line.dropFirst().dropLast()
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased()
                continue
            }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            guard !key.isEmpty else { continue }
            let value = line[line.index(after: equals)...]
                .trimmingCharacters(in: .whitespaces)
            values[section, default: [:]][key] = value
        }
    }

    func string(section: String, key: String) -> String? {
        values[section.lowercased()]?[key.lowercased()]
    }
}

nonisolated struct INISettingsSource: Equatable {
    let name: String
    let file: INIFile
}

nonisolated struct INISettings: Equatable {
    /// Low -> high priority. Reverse lookup makes later files override earlier.
    let sources: [INISettingsSource]

    func string(section: String, key: String) -> (value: String, source: String)? {
        for source in sources.reversed() {
            if let value = source.file.string(section: section, key: key) {
                return (value, source.name)
            }
        }
        return nil
    }

    /// Returns highest-priority finite float. Malformed values fall through.
    func float(section: String, key: String) -> (value: Float, source: String)? {
        for source in sources.reversed() {
            guard let raw = source.file.string(section: section, key: key) else { continue }
            guard let value = Float(raw), value.isFinite else { continue }
            return (value, source.name)
        }
        return nil
    }

    /// Loads existing candidates in declared low -> high priority.
    static func load(
        candidates: [(name: String, url: URL)],
        fileManager: FileManager = .default
    ) -> INISettings {
        let sources = candidates.compactMap { candidate -> INISettingsSource? in
            guard fileManager.fileExists(atPath: candidate.url.path) else { return nil }
            guard let data = try? Data(contentsOf: candidate.url) else { return nil }
            return INISettingsSource(name: candidate.name, file: INIFile(data: data))
        }
        return INISettings(sources: sources)
    }
}
