// Targeted active-plugin ordering for cross-plugin GMST resolution. Official
// masters are pinned first; Creation Club entries follow Skyrim.ccc; starred
// plugins.txt entries are active and preserve file order. Full load-order
// integration across every subsystem remains issue #73.

import Foundation

nonisolated enum PluginLoadOrder {
    struct Entry: Equatable {
        let name: String
        let url: URL
    }

    static func resolve(
        root: GameDataRoot,
        pluginsTextURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> [Entry] {
        let contents = (try? fileManager.contentsOfDirectory(
            atPath: root.dataURL.path(percentEncoded: false)
        )) ?? []
        let onDisk = Dictionary(
            contents.filter(Self.isPlugin).map { ($0.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let creationClub = readLines(
            root.installURL.appending(path: "Skyrim.ccc"),
            fileManager: fileManager
        )
        let pluginsURL = pluginsTextURL ?? defaultPluginsTextURL(fileManager: fileManager)
        let active = readLines(pluginsURL, fileManager: fileManager)
            .compactMap(activePluginName)

        var names = ArchiveLoadOrder.officialPlugins + creationClub + active
        var seen: Set<String> = []
        names = names.compactMap { listed in
            let key = listed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, !seen.contains(key), let actual = onDisk[key] else { return nil }
            seen.insert(key)
            return actual
        }
        return names.map {
            Entry(name: $0, url: root.dataURL.appending(path: $0, directoryHint: .notDirectory))
        }
    }

    private static func defaultPluginsTextURL(fileManager: FileManager) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Skyrim Special Edition")
            .appending(path: "plugins.txt")
    }

    private static func readLines(_ url: URL, fileManager: FileManager) -> [String] {
        guard
            fileManager.fileExists(atPath: url.path(percentEncoded: false)),
            let data = try? Data(contentsOf: url),
            let text = String(data: data, encoding: .utf8)
        else { return [] }
        return text.components(separatedBy: .newlines)
    }

    private static func activePluginName(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("*") else { return nil }
        let name = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        guard isPlugin(name) else { return nil }
        return name
    }

    private static func isPlugin(_ name: String) -> Bool {
        ["esm", "esp", "esl"].contains(URL(filePath: name).pathExtension.lowercased())
    }
}
