// `GetCurrentScene` asks the story bridge which scene holds the reference.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
import OpenSkyWorldState
import Testing

private final class FakeStoryBridge: PapyrusStoryBridge {
    var scenes: [ReferenceKey: FormID] = [:]

    func sendStoryEvent(_ event: StoryEventData) -> Bool {
        false
    }

    func startScene(_ scene: FormID, force: Bool) -> Bool {
        false
    }

    func stopScene(_ scene: FormID) {}

    func isScenePlaying(_ scene: FormID) -> Bool {
        false
    }

    func currentScene(of reference: ReferenceKey) -> FormID? {
        scenes[reference]
    }
}

@MainActor
struct PapyrusNativeSceneTests {
    @Test func currentSceneNamesTheSceneThatHoldsTheReference() throws {
        let fixture = try PapyrusNativeReferenceFixture.make()
        let read = { fixture.call("GetCurrentScene", returnType: .object("Scene")) }
        guard case .failed = read() else {
            Issue.record("GetCurrentScene answered without the scene runtime")
            return
        }

        let story = FakeStoryBridge()
        fixture.session.bridge.story = story
        #expect(read() == .returned(.none))
        story.scenes[fixture.key] = FormID(PapyrusNativeReferenceFixture.doorID)
        #expect(read() == .returned(.object(fixture.handle(PapyrusNativeReferenceFixture.doorID))))
    }
}
