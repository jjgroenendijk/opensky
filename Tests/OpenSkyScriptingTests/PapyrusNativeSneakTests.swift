// `StartSneaking` toggles the player's sneak and leaves another actor as it is.

import Foundation
import OpenSkyFormatsESM
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
import Testing

@MainActor
struct PapyrusNativeSneakTests {
    @Test func startSneakingTogglesOnlyThePlayer() throws {
        let fixture = try PapyrusNativeReferenceFixture.make()
        var toggles = 0
        fixture.session.bridge.togglePlayerSneaking = { toggles += 1 }
        let sneak = { (receiver: PapyrusObjectHandle?) in
            fixture.registry.invoke(PapyrusWorldFixture.methodCall(
                "Actor", "StartSneaking", receiver: receiver
            ))
        }
        #expect(sneak(fixture.receiver) == .returned(.none))
        #expect(toggles == 0)
        let player = try #require(fixture.session.bridge.objectHandle(for: .player))
        #expect(sneak(player) == .returned(.none))
        #expect(toggles == 1)
    }
}
