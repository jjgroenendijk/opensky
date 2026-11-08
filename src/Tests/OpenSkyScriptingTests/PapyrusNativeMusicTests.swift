// `MusicType.Add` and `Remove` reach the music port with the receiver's key.

import Foundation
import OpenSkyFormatsESM
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
import Testing

private final class FakeMusic: PapyrusMusicControlling {
    var stack: [ReferenceKey] = []
    var playable = true

    func addMusic(_ music: ReferenceKey) -> Bool {
        guard playable else { return false }
        stack.append(music)
        return true
    }

    func removeMusic(_ music: ReferenceKey) {
        stack.removeAll { $0 == music }
    }
}

@MainActor
struct PapyrusNativeMusicTests {
    @Test func addAndRemoveReachTheMusicPort() throws {
        let fixture = try PapyrusNativeReferenceFixture.make()
        let musicType = fixture.handle(PapyrusNativeReferenceFixture.doorID)
        let key = PapyrusNativeReferenceFixture.key(PapyrusNativeReferenceFixture.doorID)
        let invoke = { (name: String) in
            fixture.registry.invoke(PapyrusWorldFixture.methodCall(
                "MusicType", name, receiver: musicType
            ))
        }
        guard case .failed = invoke("Add") else {
            Issue.record("Add answered without the music director")
            return
        }

        let music = FakeMusic()
        fixture.session.bridge.music = music
        #expect(invoke("Add") == .returned(.none))
        #expect(music.stack == [key])
        #expect(invoke("Remove") == .returned(.none))
        #expect(music.stack.isEmpty)

        music.playable = false
        guard case .failed = invoke("Add") else {
            Issue.record("Add accepted a music type with no playable track")
            return
        }
    }
}
