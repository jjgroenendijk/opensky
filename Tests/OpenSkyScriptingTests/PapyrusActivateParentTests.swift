// `XAPR` activate parents: activating a reference also activates the references
// that name it, each with its parent as the activator.

import Foundation
import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
@testable import OpenSkyWorldState
import Testing

@MainActor
struct PapyrusActivateParentTests {
    private static let plateID: UInt32 = 0x0010
    private static let trapID: UInt32 = 0x0020
    private static let hitID: UInt32 = 0x0030

    @Test func activationReachesEveryActivateChildOnce() throws {
        let note = PapyrusWorldFixture.probeBody(note: "trap.onactivate")
        let trapScript = PapyrusWorldFixture.eventScript("Trap", events: [("OnActivate", note)])
        let entries = try [
            PapyrusWorldFixture.referenceEntry(objectID: Self.plateID, scripts: []),
            PapyrusWorldFixture.referenceEntry(
                objectID: Self.trapID,
                scripts: [VMADFixture.Script("Trap", properties: [])],
                activateParents: [Self.plateID, Self.hitID]
            ),
            // A cycle back to the trap must not activate it a second time.
            PapyrusWorldFixture.referenceEntry(
                objectID: Self.hitID, scripts: [], activateParents: [Self.trapID]
            )
        ]
        let session = PapyrusWorldFixture.session(objects: [trapScript], entries: entries)
        PapyrusWorldFixture.drain(session.world)

        let outcome = session.bridge.activate(key(Self.plateID), by: .player, togglesOpen: false)
        #expect(outcome.queuedEvents == 1)
        let trap = session.worldState.component(
            ReferenceActivationState.self,
            for: key(Self.trapID)
        )
        #expect(trap?.activationCount == 1)
        #expect(trap?.lastActivator == key(Self.plateID))
        let hit = session.worldState.component(ReferenceActivationState.self, for: key(Self.hitID))
        #expect(hit?.lastActivator == key(Self.trapID))
        PapyrusWorldFixture.drain(session.world)
        #expect(session.dispatch.notes == ["trap.onactivate"])
    }

    private func key(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: PapyrusWorldFixture.pluginName, objectID: objectID)
    }
}
