// SCNS, SCNP, SMQS, DLBS, MSTS, and QTRK chunks: a scene mid-phase, a paused scene,
// a story-manager start record, an exclusive branch, the misc stats, and an untracked
// quest come back as they were; an untouched session writes none.

import Foundation
@testable import OpenSkyDialogueInterface
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyQuestsInterface
@testable import OpenSkySave
import OpenSkySaveFixtures
@testable import OpenSkyWorldState
import Testing

@MainActor
struct StorySaveTests {
    private let scene = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0004_0000)
    private let quest = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0001_0100)
    private let speaker = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0001_3BBD)
    private let sceneState = SceneRuntimeState(
        phase: 1, phaseEntered: true,
        running: [
            SceneActionProgress(action: 2, startedAt: 812.5, duration: 5),
            SceneActionProgress(action: 3, startedAt: 812.5, duration: nil)
        ],
        completed: [0, 1]
    )
    private let pausedScene = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0004_0001)
    private let pausedState = SceneRuntimeState(
        phase: 0, phaseEntered: true,
        running: [SceneActionProgress(action: 0, startedAt: 10, duration: 4)],
        pausedAt: 12.5
    )
    private let questState = StoryManagerQuestState(lastStartSeconds: 86400.25, startCount: 3)
    private let branchState = DialogueBranchState(exclusiveBranch: FormID(0x0002_1A3C))
    private let stats = MiscStatsState(values: ["Bribes": 2, "Quests Completed": -1])
    private let untracked = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0004_0002)

    private func snapshot() -> WorldStateSnapshot {
        OpenSkySaveFixture.snapshot(
            [
                OpenSkySaveFixture.entry(key: scene, cell: nil, components: [sceneState.erased]),
                OpenSkySaveFixture.entry(
                    key: pausedScene, cell: nil, components: [pausedState.erased]
                ),
                OpenSkySaveFixture.entry(key: quest, cell: nil, components: [questState.erased]),
                OpenSkySaveFixture.entry(key: speaker, cell: nil, components: [branchState.erased]),
                OpenSkySaveFixture.entry(key: .player, cell: nil, components: [stats.erased]),
                OpenSkySaveFixture.entry(
                    key: untracked, cell: nil,
                    components: [QuestTrackingState(isTracked: false).erased]
                )
            ],
            bystanderCell: OpenSkySaveFixture.riverwood
        )
    }

    @Test func storyStateSurvivesAnEncodeAndDecode() throws {
        let original = snapshot()
        let data = OpenSkySaveFixture.encode(original)
        for tag in ["SCNS", "SCNP", "SMQS", "DLBS", "MSTS", "QTRK"] {
            #expect(data.range(of: Data(tag.utf8)) != nil)
        }
        let file = try OpenSkySaveDecoder.decode(data)
        #expect(file.snapshot == original)
        let store = WorldStateStore()
        store.restore(from: file.snapshot)
        #expect(store.component(SceneRuntimeState.self, for: scene) == sceneState)
        #expect(store.component(SceneRuntimeState.self, for: pausedScene) == pausedState)
        #expect(store.component(StoryManagerQuestState.self, for: quest) == questState)
        #expect(store.component(DialogueBranchState.self, for: speaker) == branchState)
        #expect(store.miscStats == stats)
        #expect(store.component(QuestTrackingState.self, for: untracked)?.isTracked == false)
    }

    @Test func noStoryStateWritesNoChunk() {
        let data = OpenSkySaveFixture.encode(
            OpenSkySaveFixture.snapshot([], bystanderCell: OpenSkySaveFixture.riverwood)
        )
        for tag in ["SCNS", "SCNP", "SMQS", "DLBS", "MSTS", "QTRK"] {
            #expect(data.range(of: Data(tag.utf8)) == nil)
        }
    }

    @Test func aRunningCountPastThePayloadIsRejected() {
        var payload = Data()
        payload.appendUInt32(1)
        payload.append(contentsOf: [1, 0, 0, 0, 0, 0, 0, 0])
        payload.appendUInt32(0)
        payload.append(0)
        payload.appendUInt32(1_000_000)
        #expect(throws: OpenSkySaveError.self) {
            try OpenSkySaveStoryDecoder.decodeScenes(payload)
        }
    }
}
