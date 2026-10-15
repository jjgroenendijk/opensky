// `StartSneaking` puts the player into sneak and leaves another actor as it is.

import Foundation
import OpenSkyFormatsESM
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
import Testing

@MainActor
struct PapyrusNativeSneakTests {
    @Test func startSneakingMovesOnlyThePlayer() throws {
        let fixture = try PapyrusNativeReferenceFixture.make()
        var starts = 0
        fixture.session.bridge.startPlayerSneaking = { starts += 1 }
        let sneak = { (receiver: PapyrusObjectHandle?) in
            fixture.registry.invoke(PapyrusWorldFixture.methodCall(
                "Actor", "StartSneaking", receiver: receiver
            ))
        }
        #expect(sneak(fixture.receiver) == .returned(.none))
        #expect(starts == 0)
        let player = try #require(fixture.session.bridge.objectHandle(for: .player))
        #expect(sneak(player) == .returned(.none))
        #expect(starts == 1)
    }
}
