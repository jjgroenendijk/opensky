// The facts the combat helper rules read through the combat world's ports.

import OpenSkyCombatAdapters
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkySessionTesting
import Testing

@MainActor
struct CombatAssistFactsTests {
    private let host = CombatHost()
    private var adapter: CombatWorldAdapter {
        CombatWorldAdapter(game: host)
    }

    private static let foe = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)

    @Test func withoutASessionOrRecordsTheHelperFactsAreEmpty() {
        #expect(adapter.aggroRadius(of: Self.foe) == nil)
        #expect(adapter.playerViewFOVYRadians == nil)
        #expect(!adapter.playerRuns)
        #expect(adapter.playerViewAspect == nil)
        #expect(adapter.playerMount == nil)
        host.fakeMountWorld.riddenMount = Self.foe
        #expect(adapter.playerMount == Self.foe)
        #expect(adapter.attackStagger(of: Self.foe, event: "attackStart") == nil)
    }
}
