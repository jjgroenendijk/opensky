// A script that stops its own quest during a drain retires queued events the drain
// already passed, and the drain must still finish cleanly.

import FormatsTesting
import Foundation
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
import Testing

@MainActor
struct PapyrusWorldDrainTests {
    @Test func stoppingTheQuestMidDrainDropsItsLaterFragments() throws {
        let stage = PapyrusQuestFixture.fragmentStage
        let script = PapyrusQuestFixture.fragmentScript
        let quest = try PapyrusQuestFixture.quest(fragments: [
            QuestFixture.Fragment(stage: stage, script: script, function: "Fragment_0"),
            QuestFixture.Fragment(
                stage: stage, logEntry: 1, script: script, function: "Fragment_1"
            )
        ])
        let session = PapyrusQuestFixture.session(
            quest: quest,
            objects: PapyrusQuestFixture.objects(fragmentFunctions: [
                ("Fragment_0", PapyrusWorldFixture.probeBody(note: "stop")),
                ("Fragment_1", PapyrusWorldFixture.probeBody(note: "after"))
            ])
        )
        PapyrusWorldFixture.drain(session.world)
        session.dispatch.probeHandler = { call, _ in
            guard call.arguments.first == .string("stop") else { return nil }
            try? session.bridge.stopQuest(for: PapyrusQuestFixture.questKey)
            return .returned(.none)
        }
        try session.bridge.setQuestStage(stage, for: PapyrusQuestFixture.questKey)
        PapyrusWorldFixture.drain(session.world)
        #expect(!session.dispatch.notes.contains("after"))
        #expect(session.world.eventQueue.isEmpty)
    }
}
