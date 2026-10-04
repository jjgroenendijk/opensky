// Records outside Skyrim.esm against the user's install: DLC scenes and story nodes
// name quests the load-order quest store holds, DLC text resolves in its own
// plugin's string tables, and NPC and item names come from FULL.
// Run with `make test-real T='LoadOrderTextRealDataTests'`.

import Foundation
@testable import OpenSkyDialogue
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyInventoryInterface
@testable import OpenSkyWorld
import Testing

struct LoadOrderTextRealDataTests {
    private static let basePlugin = "Skyrim.esm"

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func dlcScenesAndStoryNodesNameStoredQuests() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let plugins = ActivePluginFiles.load(root: root)
        let quests = QuestStore(plugins: plugins)
        let data = StoryData.load(plugins: plugins)
        let scenes = try #require(data.scenes)
        let catalog = SceneCatalog(store: scenes, resolver: quests.resolver)
        let dlcScenes = scenes.scenes.records.filter { $0.sourcePlugin != Self.basePlugin }
        let unresolvedScenes = dlcScenes.filter { record in
            guard record.record.quest != nil else { return false }
            let entry = quests.resolver.localFormID(of: record.id).flatMap { catalog.scene($0) }
            return entry?.quest.flatMap { quests.quest($0) } == nil
        }
        #expect(!dlcScenes.isEmpty)
        #expect(unresolvedScenes.isEmpty, "\(unresolvedScenes.prefix(5).map(\.id))")

        let story = try #require(data.storyManager)
        let dlcNodes = story.nodes.records.filter {
            $0.sourcePlugin != Self.basePlugin && !$0.record.quests.isEmpty
        }
        let unresolvedNodes = dlcNodes.filter { node in
            node.record.quests.contains { entry in
                let id = story.nodes.index.resolvedID(entry.quest, fromPlugin: node.sourcePlugin)
                return id.flatMap { quests.resolver.localFormID(of: $0) }
                    .flatMap { quests.quest($0) } == nil
            }
        }
        #expect(!dlcNodes.isEmpty)
        #expect(unresolvedNodes.isEmpty, "\(unresolvedNodes.prefix(5).map(\.id))")
        print("[INFO] DLC scenes \(dlcScenes.count), DLC quest nodes \(dlcNodes.count)")
    }

    /// Every DLC MESG and LSCR whose text is a string ID resolves in its own plugin's tables.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func dlcMessagesAndLoadingScreensReadTheirOwnTables() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let index = RecordIndex(
            plugins: ActivePluginFiles.load(root: root),
            recordTypes: PresentationRecordStore.recordTypes
        )
        let store = PresentationRecordStore(index: index)
        let strings = LocalizedStrings(
            vfs: VirtualFileSystem(root: root),
            pluginName: Self.basePlugin
        )
        var checked = 0
        var missing: [String] = []
        var samples: [String] = []
        let check = { (text: LString?, kind: StringTable.Kind, plugin: String, name: String) in
            // ID 0 is authored "no text", as on the alias-name MESG records.
            guard case let .tableID(id) = text, id != 0, plugin != Self.basePlugin else { return }
            checked += 1
            guard let resolved = strings.scoped(to: plugin).resolve(text, kind: kind) else {
                missing.append("\(plugin) \(name)")
                return
            }
            if samples.count < 6 {
                samples.append("  \(name): \(resolved.prefix(60))")
            }
        }
        for screen in store.loadScreens.records {
            let name = screen.record.editorID ?? screen.id.description
            check(screen.record.description, .strings, screen.sourcePlugin, name)
        }
        for message in store.messages.records {
            let name = message.record.editorID ?? message.id.description
            check(message.record.description, .dlstrings, message.sourcePlugin, name)
        }
        print(["[INFO] DLC text fields \(checked), missing \(missing.count)"] + samples)
        #expect(checked > 100)
        #expect(missing.isEmpty, "\(missing.prefix(8))")
        let vampires = try #require(store.loadScreens.record(editorID: "DLC1Vampires"))
        #expect(vampires.sourcePlugin == "Dawnguard.esm")
        let text = strings.scoped(to: vampires.sourcePlugin).resolve(vampires.record.description)
        #expect(text?.hasPrefix("Each day spent as a vampire") == true)
    }

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func npcAndItemNamesComeFromFull() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: Self.basePlugin))
        let strings = LocalizedStrings(
            vfs: VirtualFileSystem(root: root),
            pluginName: Self.basePlugin
        )
        let baselines = InventoryBaselineResolver.build(from: file, strings: strings)

        let sword = try #require(baselines.items.definition(editorID: "IronSword"))
        #expect(sword.name == .inline("Iron Sword"))
        let hulda = try #require(baselines.actors.actors.values.first { $0.editorID == "Hulda" })
        let name = try baselines.actors.resolveName(base: hulda.formID)
        #expect(strings.resolve(name.value) == "Hulda")
    }
}
