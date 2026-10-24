// Reads Steam's list of library folders, so an install on a second drive is found
// without setup. The file is Valve's KeyValues text: `"path"  "/Volumes/data/steam"`.

import Foundation

nonisolated public enum SteamLibraryFolders: Sendable {
    /// Steam's library list on macOS.
    public static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Steam/steamapps/libraryfolders.vdf")
    }

    /// The value of every `"path"` key, in file order. Malformed lines are skipped.
    public static func paths(in text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = quotedFields(in: line)
            guard fields.count == 2, fields[0].lowercased() == "path" else { return nil }
            return fields[1]
        }
    }

    /// The Skyrim SE folder inside each library listed in `fileURL`, or none when
    /// the file is missing or unreadable.
    public static func skyrimInstallCandidates(fileURL: URL = defaultFileURL) -> [URL] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return paths(in: text).map { library in
            URL(filePath: library, directoryHint: .isDirectory)
                .appending(path: "steamapps/common/Skyrim Special Edition")
        }
    }

    /// Quoted strings on one line. KeyValues escapes a backslash or quote with `\`.
    private static func quotedFields(in line: Substring) -> [String] {
        var fields: [String] = []
        var current: String?
        var escaped = false
        for character in line {
            if var open = current {
                if escaped {
                    open.append(character)
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    fields.append(open)
                    current = nil
                    continue
                } else {
                    open.append(character)
                }
                current = open
            } else if character == "\"" {
                current = ""
            }
        }
        return fields
    }
}
