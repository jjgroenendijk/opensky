// `audio voice-sweep`: the two checks that settle the `.fuz` work.
//
// Naming — the community descriptions of the voice-file naming scheme disagree
// (item 17.5), so the rule in `VoiceFilePath` is derived from the archive
// itself. This sweep re-derives a name for every INFO response in every loaded
// plugin and compares the result against the archive listing, reporting how
// many archive names the rule explains and printing the ones it does not.
//
// Framing — every `.fuz` entry is framed through the production `FUZFile`
// parser and its payload through `XWMFile`, one file at a time (bytes are
// released before the next path is opened), so the walk stays flat in memory
// over all 75,408 entries. `--limit` bounds the walk and the report states
// exactly how many entries were skipped.

import Foundation

enum AudioVoiceSweep {
    /// Plugins that ship voice archives. Read in this order so the report is
    /// stable; each is skipped when the install does not carry it.
    static let voicePlugins = [
        "Skyrim.esm", "Update.esm", "Dawnguard.esm", "HearthFires.esm", "Dragonborn.esm"
    ]

    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let limit = try scanner.option("--limit").map {
            guard let value = Int($0), value > 0 else {
                throw CLIError.usage("--limit needs a positive integer")
            }
            return value
        }
        let namesOnly = scanner.flag("--names-only")
        try scanner.finish()

        let vfs = context.makeFileSystem()
        let paths = vfs.archiveEntries().map(\.path)
            .filter { $0.lowercased().hasSuffix(".fuz") }
        print("[INFO] voice sweep: \(paths.count) .fuz entries")
        try checkNaming(context: context, paths: paths)
        guard !namesOnly else { return }
        try frameAll(vfs: vfs, paths: paths, limit: limit)
    }

    // MARK: - Naming derivation

    /// Rebuilds every voice file name the records imply and measures it against
    /// the names the archive actually holds, per plugin.
    private static func checkNaming(context: CLIContext, paths: [String]) throws {
        // Every plugin's DIAL and QUST indexes are built before any name is
        // derived: a topic in one plugin is regularly owned by a quest defined
        // in one of its masters, so a per-plugin pass would lose the quest half
        // of the name for exactly those lines.
        var dialogueStores: [(name: String, store: DialogueStore)] = []
        var questStores: [String: QuestStore] = [:]
        for pluginName in voicePlugins {
            let url = context.root.dataURL.appending(path: pluginName)
            guard let file = try? ESMFile(url: url) else { continue }
            questStores[pluginName.lowercased()] = QuestStore(file: file, pluginName: pluginName)
            let dialogue = DialogueStore(file: file, pluginName: pluginName)
            if dialogue.infoCount > 0 {
                dialogueStores.append((pluginName, dialogue))
            }
        }
        var report = VoiceNameReport()
        for (pluginName, dialogue) in dialogueStores {
            let locator = VoiceLineLocator(dialogue: dialogue, questStores: questStores)
            report.record(
                plugin: pluginName,
                derived: derivedNames(locator: locator, dialogue: dialogue),
                actual: actualNames(paths: paths, plugin: pluginName)
            )
        }
        report.print()
    }

    private static func derivedNames(
        locator: VoiceLineLocator, dialogue: DialogueStore
    ) -> [VoiceFileNameDerivation] {
        var names: [VoiceFileNameDerivation] = []
        for topic in dialogue.sortedTopics() {
            for info in dialogue.infos(for: topic.formID) {
                names.append(contentsOf: locator.fileNames(info: info))
            }
        }
        return names
    }

    /// Voice file names the archive holds under one plugin's directory. The
    /// archive stores one copy per voice type, so the name set is what the
    /// records can be compared against.
    private static func actualNames(paths: [String], plugin: String) -> Set<String> {
        let prefix = "sound\\voice\\\(plugin.lowercased())\\"
        var names: Set<String> = []
        for path in paths where path.hasPrefix(prefix) {
            guard let name = path.split(separator: "\\").last else { continue }
            names.insert(String(name))
        }
        return names
    }

    // MARK: - Framing

    private static func frameAll(vfs: VirtualFileSystem, paths: [String], limit: Int?) throws {
        let walked = limit.map { Array(paths.prefix($0)) } ?? paths
        var tally = VoiceFramingTally()
        tally.skipped = paths.count - walked.count
        for path in walked {
            do {
                let fuz = try FUZFile(data: vfs.contents(forPath: path))
                tally.record(fuz)
                try tally.record(fuz.audio())
            } catch let error as FUZError {
                tally.note(path: path, error: error)
            } catch let error as XWMError {
                tally.note(path: path, error: error)
            } catch {
                tally.failures.append((path, String(describing: error)))
            }
        }
        tally.print(total: paths.count)
        guard tally.failures.isEmpty else {
            throw CLIError.failure(
                "audio voice-sweep failed: \(tally.failures.count) files did not frame"
            )
        }
    }
}
