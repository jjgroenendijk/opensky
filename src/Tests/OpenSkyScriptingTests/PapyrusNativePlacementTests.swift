// `PlaceActorAtMe` spawns a saved reference where the receiver stands, and
// `Utility.IsInMenuMode` answers for a VM that a menu pauses.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct PapyrusNativePlacementTests {
    private static let actorBaseID: UInt32 = 0x0500

    @Test func placeActorAtMeSpawnsTheBaseAtTheReceiver() throws {
        let fixture = try PapyrusNativeReferenceFixture.make()
        let result = fixture.registry.invoke(PapyrusWorldFixture.methodCall(
            "ObjectReference", "PlaceActorAtMe", receiver: fixture.receiver,
            arguments: [.object(fixture.handle(Self.actorBaseID))]
        ))
        guard case let .returned(.object(handle)) = result else {
            Issue.record("PlaceActorAtMe returned \(result)")
            return
        }
        let placed = try #require(fixture.session.bridge.referenceKey(for: handle))
        let spawn = try #require(
            fixture.session.worldState.component(ReferenceSpawnState.self, for: placed)
        )
        #expect(spawn.base == FormID(Self.actorBaseID))
        #expect(spawn.placement.position == SIMD3(1, 2, 3))
    }

    @Test func isInMenuModeIsFalseWhileAScriptRuns() throws {
        let fixture = try PapyrusNativeReferenceFixture.make()
        let result = fixture.registry.invoke(PapyrusNativeCall(
            kind: .staticFunction, scriptName: "Utility", functionName: "IsInMenuMode",
            receiver: nil, arguments: [], returnType: .boolean
        ))
        #expect(result == .returned(.boolean(false)))
    }
}
