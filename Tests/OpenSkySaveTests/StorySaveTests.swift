// SCNS, SMQS, and DLBS chunks: a scene mid-phase, a story-manager start record,
// and an exclusive branch come back as they were; an untouched session writes none.

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
    private let questState = StoryManagerQuestState(lastStartSeconds: 86400.25, startCount: 3)
    private let branchState = DialogueBranchState(exclusiveBranch: FormID(0x0002_1A3C))

    private func snapshot() -> WorldStateSnapshot {
        OpenSkySaveFixture.snapshot(
            [
                OpenSkySaveFixture.entry(key: scene, cell: nil, components: [sceneState.erased]),
                OpenSkySaveFixture.entry(key: quest, cell: nil, components: [questState.erased]),
                OpenSkySaveFixture.entry(key: speaker, cell: nil, components: [branchState.erased])
            ],
            bystanderCell: OpenSkySaveFixture.riverwood
        )
    }

    @Test func storyStateSurvivesAnEncodeAndDecode() throws {
        let original = snapshot()
        let data = OpenSkySaveFixture.encode(original)
        for tag in ["SCNS", "SMQS", "DLBS"] {
            #expect(data.range(of: Data(tag.utf8)) != nil)
        }
        let file = try OpenSkySaveDecoder.decode(data)
        #expect(file.snapshot == original)
        let store = WorldStateStore()
        store.restore(from: file.snapshot)
        #expect(store.component(SceneRuntimeState.self, for: scene) == sceneState)
        #expect(store.component(StoryManagerQuestState.self, for: quest) == questState)
        #expect(store.component(DialogueBranchState.self, for: speaker) == branchState)
    }

    @Test func noStoryStateWritesNoChunk() {
        let data = OpenSkySaveFixture.encode(
            OpenSkySaveFixture.snapshot([], bystanderCell: OpenSkySaveFixture.riverwood)
        )
        for tag in ["SCNS", "SMQS", "DLBS"] {
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
