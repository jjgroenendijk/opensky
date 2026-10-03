// Scene playback against the user's install. `DialogueWinterholdInnInitialScene`
// is four dialogue phases between two forced-reference actors, so it plays with
// no loaded cell. Pins were observed on 2026-10-03 against the shipped `Skyrim.esm`.

import Foundation
@testable import OpenSkyConditions
@testable import OpenSkyDialogue
@testable import OpenSkyDialogueInterface
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyQuests
@testable import OpenSkyQuestsInterface
@testable import OpenSkyWorld
@testable import OpenSkyWorldState
import OpenSkyWorldTesting
import Testing

struct SceneRealDataTests {
    private static let sceneEditorID = "DialogueWinterholdInnInitialScene"
    /// The two speakers' ACHR records, the scene's forced-reference aliases.
    private static let speakers: Set<UInt32> = [0x0001_E7D6, 0x0001_C18D]
    private static let expectedCatalogCount = 1706
    /// One line per phase, in phase order, alternating between the two speakers.
    private static let expectedLines: [(speaker: UInt32, info: UInt32)] = [
        (0x0001_E7D6, 0x000B_1138), (0x0001_C18D, 0x000B_113C),
        (0x0001_E7D6, 0x000B_1139), (0x0001_C18D, 0x000B_113B)
    ]

    @MainActor
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func playsAFourPhaseSceneToTheEnd() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let quests = QuestStore(file: file, pluginName: "Skyrim.esm")
        let catalog = SceneCatalog(
            store: SceneStore(plugins: [(name: "Skyrim.esm", file: file)]),
            resolver: quests.resolver
        )
        #expect(catalog.count == Self.expectedCatalogCount, "scene catalog drift")
        let entry = try #require(catalog.scene(editorID: Self.sceneEditorID))
        let questID = try #require(entry.scene.quest)

        let bases = Self.bases(of: Self.speakers, in: file)
        #expect(bases.count == Self.speakers.count, "speaker ACHR missing")
        let store = WorldStateStore()
        let questRuntime = QuestRuntime(store: store, quests: quests)
        try questRuntime.startQuest(questID)
        var context = try ConditionContext(
            references: ConditionEvaluatorFixture.references(
                bases.map { (formID: $0.key, base: $0.value) }
            ),
            subject: nil,
            target: .player
        )
        context.aliases = questRuntime.aliasResolution()
        let dialogue = DialogueRuntime(
            store: store,
            dialogue: DialogueStore(file: file, pluginName: "Skyrim.esm", localized: true),
            questStates: questRuntime.resolution(),
            context: context,
            registry: .standard
        )
        var runtime = SceneRuntime(catalog: catalog, dialogue: dialogue)
        var events = try runtime.start(entry.formID)
        while runtime.isPlaying(entry.formID), runtime.now < 120 {
            runtime.now += 1
            events += runtime.tick()
        }

        let lines = events.compactMap { event -> SceneLine? in
            if case let .line(line) = event.step {
                return line
            }
            return nil
        }
        #expect(lines.map(\.info.rawValue) == Self.expectedLines.map(\.info))
        #expect(lines.map(\.speaker) == Self.expectedLines.map {
            .plugin(name: "skyrim.esm", objectID: $0.speaker)
        })
        #expect(lines.allSatisfy { dialogue.hasBeenSaid($0.info) })
        #expect(events.last?.step == .ended(.finished))
        #expect(!runtime.isPlaying(entry.formID))
    }

    /// Selection matches a speaker by its base form, so each ACHR's `NAME` is read.
    private static func bases(of references: Set<UInt32>, in file: ESMFile) -> [UInt32: UInt32] {
        var found: [UInt32: UInt32] = [:]
        ESMWalk.forEachRecord(in: file) { record in
            guard
                record.type == "ACHR", references.contains(record.formID),
                let name = (try? record.fields())?.first(where: { $0.type == "NAME" }),
                name.data.count == 4
            else {
                return true
            }
            found[record.formID] = name.data.reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            return found.count < references.count
        }
        return found
    }
}
