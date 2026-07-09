// Orders the .bsa archives the engine opens, mirroring the game's rules:
// ini resource lists first, then archives named after plugins present in
// `Data/`. Later archives take priority over earlier ones on conflicting
// paths; loose files beat every archive (see VirtualFileSystem).
//
// Reference: UESP "Skyrim Mod:Archive File Format" (load-order notes) —
//   https://en.uesp.net/wiki/Skyrim_Mod:Archive_File_Format
// Vanilla resource lists observed in Skyrim_Default.ini shipped with SSE 1.6.
// Full resolution rules + provisional plugin ordering: docs/formats/vfs.md.

import Foundation
import OSLog

nonisolated enum ArchiveLoadOrder {
    private static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "VFS"
    )

    /// Vanilla `[Archive]` resource lists (Skyrim_Default.ini, SSE 1.6):
    /// sResourceArchiveList followed by sResourceArchiveList2. Fallback when
    /// no ini in the install root is readable.
    static let vanillaResourceArchives = [
        "Skyrim - Misc.bsa",
        "Skyrim - Shaders.bsa",
        "Skyrim - Interface.bsa",
        "Skyrim - Animations.bsa",
        "Skyrim - Meshes0.bsa",
        "Skyrim - Meshes1.bsa",
        "Skyrim - Sounds.bsa",
        "Skyrim - Voices_en0.bsa",
        "Skyrim - Textures0.bsa",
        "Skyrim - Textures1.bsa",
        "Skyrim - Textures2.bsa",
        "Skyrim - Textures3.bsa",
        "Skyrim - Textures4.bsa",
        "Skyrim - Textures5.bsa",
        "Skyrim - Textures6.bsa",
        "Skyrim - Textures7.bsa",
        "Skyrim - Textures8.bsa",
        "Skyrim - Patch.bsa"
    ]

    /// Official plugins (game + DLC .esm files) in canonical load order.
    /// Their plugin-named archives come before any other plugin's.
    static let officialPlugins = [
        "Skyrim.esm",
        "Update.esm",
        "Dawnguard.esm",
        "HearthFires.esm",
        "Dragonborn.esm"
    ]

    /// Resolves the ordered archive list for one install. First = opened
    /// first = lowest lookup priority. Names resolve case-insensitively
    /// against the on-disk `Data/` listing; listed-but-absent archives are
    /// logged and skipped (vanilla ini lists "Skyrim - Patch.bsa", which
    /// current installs no longer ship).
    static func resolve(installURL: URL, dataURL: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            atPath: dataURL.path(percentEncoded: false)
        )) ?? []
        var archivesOnDisk: [String: String] = [:] // lowercased -> on-disk name
        for name in contents where name.lowercased().hasSuffix(".bsa") {
            archivesOnDisk[name.lowercased()] = name
        }

        var ordered: [String] = []
        var seen: Set<String> = []
        for name in resourceListNames(installURL: installURL) {
            let key = name.lowercased()
            guard !seen.contains(key) else { continue }
            guard let onDisk = archivesOnDisk[key] else {
                logger.info("Archive listed but absent, skipping: \(name, privacy: .public)")
                continue
            }
            seen.insert(key)
            ordered.append(onDisk)
        }
        for candidate in pluginArchiveCandidates(dataContents: contents) {
            let key = candidate.lowercased()
            guard !seen.contains(key), let onDisk = archivesOnDisk[key] else { continue }
            seen.insert(key)
            ordered.append(onDisk)
        }
        return ordered.map { dataURL.appending(path: $0, directoryHint: .notDirectory) }
    }

    /// Reads the resource archive lists from the install root. Skyrim.ini (user
    /// override, rarely present next to the executable) wins over the shipped
    /// Skyrim_Default.ini; neither readable -> built-in vanilla list.
    private static func resourceListNames(installURL: URL) -> [String] {
        for candidate in ["Skyrim.ini", "Skyrim_Default.ini"] {
            let url = installURL.appending(path: candidate, directoryHint: .notDirectory)
            if let names = resourceLists(fromIniAt: url) {
                return names
            }
        }
        return vanillaResourceArchives
    }

    /// Concatenates the sResourceArchiveList + sResourceArchiveList2 values
    /// (comma-separated archive names). Section headers are ignored — both
    /// keys are unique across the file.
    private static func resourceLists(fromIniAt url: URL) -> [String]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        // Bethesda ini files are ASCII in practice; accept cp1252 leftovers.
        guard
            let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252) else { return nil }

        var lists: [String: [String]] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            guard key == "sresourcearchivelist" || key == "sresourcearchivelist2" else {
                continue
            }
            lists[key] = line[line.index(after: equals)...]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        guard !lists.isEmpty else { return nil }
        return (lists["sresourcearchivelist"] ?? []) + (lists["sresourcearchivelist2"] ?? [])
    }

    /// `<plugin>.bsa` + `<plugin> - Textures.bsa` for each plugin in `Data/`
    /// (SSE auto-load convention, UESP archive notes). Official plugins first
    /// in canonical order, remaining plugins alphabetically — provisional
    /// until plugins.txt load order lands (docs/todo.md open question).
    private static func pluginArchiveCandidates(dataContents: [String]) -> [String] {
        let pluginExtensions: Set = ["esm", "esp", "esl"]
        let plugins = dataContents.filter {
            pluginExtensions.contains(URL(filePath: $0).pathExtension.lowercased())
        }
        let byLowercase = Dictionary(
            plugins.map { ($0.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var ordered: [String] = []
        for official in officialPlugins {
            if let name = byLowercase[official.lowercased()] {
                ordered.append(name)
            }
        }
        let officials = Set(officialPlugins.map { $0.lowercased() })
        ordered.append(
            contentsOf: plugins
                .filter { !officials.contains($0.lowercased()) }
                .sorted { $0.lowercased() < $1.lowercased() }
        )

        return ordered.flatMap { plugin -> [String] in
            let base = URL(filePath: plugin).deletingPathExtension().lastPathComponent
            return ["\(base).bsa", "\(base) - Textures.bsa"]
        }
    }
}
