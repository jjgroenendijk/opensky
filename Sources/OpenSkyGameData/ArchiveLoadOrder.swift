// Orders the .bsa archives like the game: ini resource lists first, then archives
// named after plugins in `Data/`. Later archives win on a path conflict; loose files
// beat all archives. Source: UESP "Skyrim Mod:Archive File Format"; vanilla lists from
// Skyrim_Default.ini (SSE 1.6). See docs/formats/vfs.md.

import Foundation
import OSLog

nonisolated public enum ArchiveLoadOrder: Sendable {
    private static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "VFS"
    )

    /// Vanilla `[Archive]` resource lists (Skyrim_Default.ini, SSE 1.6):
    /// sResourceArchiveList followed by sResourceArchiveList2. Fallback when
    /// no ini in the install root is readable.
    public static let vanillaResourceArchives = [
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
    public static let officialPlugins = [
        "Skyrim.esm",
        "Update.esm",
        "Dawnguard.esm",
        "HearthFires.esm",
        "Dragonborn.esm"
    ]

    /// The ordered archive list, lowest priority first. Names match `Data/`
    /// case-insensitively; a listed but absent archive is logged and skipped.
    /// Plugin archives follow `pluginOrder`, then the alphabetical tail.
    public static func resolve(installURL: URL, dataURL: URL, pluginOrder: [String] = []) -> [URL] {
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
        let candidates = pluginArchiveCandidates(
            dataContents: contents,
            pluginOrder: pluginOrder.isEmpty ? officialPlugins : pluginOrder
        )
        for candidate in candidates {
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
        let ini = INISettings.load(candidates: [
            (
                "Skyrim_Default.ini",
                installURL.appending(path: "Skyrim_Default.ini", directoryHint: .notDirectory)
            ),
            (
                "Skyrim.ini",
                installURL.appending(path: "Skyrim.ini", directoryHint: .notDirectory)
            )
        ])
        let first = ini.string(section: "Archive", key: "sResourceArchiveList")?.value
        let second = ini.string(section: "Archive", key: "sResourceArchiveList2")?.value
        guard first != nil || second != nil else { return vanillaResourceArchives }
        return archiveNames(first) + archiveNames(second)
    }

    private static func archiveNames(_ value: String?) -> [String] {
        value?.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty } ?? []
    }

    /// `<plugin>.bsa` and `<plugin> - Textures.bsa` in `pluginOrder`, then the rest of
    /// `Data/` alphabetically. The game skips inactive plugins; this keeps them at the
    /// lowest priority, so mods still load without plugins.txt (docs/formats/plugins-txt.md).
    private static func pluginArchiveCandidates(
        dataContents: [String],
        pluginOrder: [String]
    ) -> [String] {
        let pluginExtensions: Set = ["esm", "esp", "esl"]
        let plugins = dataContents.filter {
            pluginExtensions.contains(URL(filePath: $0).pathExtension.lowercased())
        }
        let byLowercase = Dictionary(
            plugins.map { ($0.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var ordered: [String] = []
        var named: Set<String> = []
        for listed in pluginOrder {
            let key = listed.lowercased()
            guard !named.contains(key), let name = byLowercase[key] else { continue }
            named.insert(key)
            ordered.append(name)
        }
        ordered.append(
            contentsOf: plugins
                .filter { !named.contains($0.lowercased()) }
                .sorted { $0.lowercased() < $1.lowercased() }
        )

        return ordered.flatMap { plugin -> [String] in
            let base = URL(filePath: plugin).deletingPathExtension().lastPathComponent
            return ["\(base).bsa", "\(base) - Textures.bsa"]
        }
    }
}
