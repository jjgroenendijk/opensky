// The scene, story-manager, and dialogue-branch half of the world-provider fake:
// one scene the controls start and stop, one event the Fire button counts.

@testable import OpenSkyDialogue
@testable import OpenSkyFormatsESM
@testable import OpenSkyQuests

struct FakeStoryState {
    var scenePlaying = false
    var lastScene = "none"
    var fired: [String] = []
    var lastFilter = ""
}

extension FakeWorldProviders {
    static let sceneRow = "TestScene"

    var sceneSnapshot: SceneControlSnapshot {
        SceneControlSnapshot(
            sceneCount: 1,
            playing: story.scenePlaying
                ? [ScenePlayingRow(
                    editorID: Self.sceneRow, phase: 1, phaseCount: 3,
                    runningActions: [0]
                )]
                : [],
            trace: [],
            lines: [],
            lastOutcome: story.lastScene
        )
    }

    func sceneRows(matching filter: String) -> [SceneListRow] {
        story.lastFilter = filter
        return [SceneListRow(
            editorID: Self.sceneRow, phaseCount: 3, actionCount: 2, actorCount: 1,
            isPlaying: story.scenePlaying
        )]
    }

    func startScene(editorID: String) {
        story.scenePlaying = editorID == Self.sceneRow
        story.lastScene = story.scenePlaying ? "started" : "no scene named \(editorID)"
    }

    func stopScene(editorID: String) {
        story.scenePlaying = false
        story.lastScene = "stopped"
    }

    var storyManagerSnapshot: StoryManagerSnapshot {
        StoryManagerSnapshot(
            nodeCount: 3,
            events: [StoryEventRow(code: "KILL", eventNodeCount: 1, firedCount: story.fired.count)],
            walkLines: story.fired.map { "\($0): entered" },
            droppedWalkLines: 0,
            sessionStart: "1 of 1 started, 0 plugins without a list, 0 broken",
            lastOutcome: story.fired.last
        )
    }

    func storyTree(event code: String) -> [String] {
        code == "KILL" ? ["KillEvents", "  KillQuests: TestQuest"] : []
    }

    func fireStoryEvent(code: String, keyword: FormID?, value1: Float) {
        story.fired.append(code)
    }

    var dialogueBranchSnapshot: DialogueBranchSnapshot {
        DialogueBranchSnapshot(
            branchCount: 2, blockingCount: 1, offeredCount: 1, notEntryCount: 3,
            blockedCount: 0, blockingBranch: nil, exclusiveBranch: nil
        )
    }

    func branchRows(matching filter: String) -> [String] {
        ["TestBranch: top-level; starts TestTopic; 2 topics"]
    }
}
