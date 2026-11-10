// A cell that leaves the scene retires the scripts on its references through the bridge.

import OpenSkyFormatsTesting
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import Testing

@MainActor
struct PapyrusBridgeCellDetachTests {
    @Test func detachingACellRetiresTheScriptsOnIt() throws {
        let entry = try PapyrusWorldFixture.referenceEntry(
            objectID: 1, scripts: [VMADFixture.Script("AScript", properties: [])]
        )
        let session = PapyrusWorldFixture.session(
            objects: [PapyrusWorldFixture.eventScript("AScript", events: [])],
            entries: [entry]
        )
        PapyrusWorldFixture.drain(session.world)
        #expect(!session.world.instancesByKey.isEmpty)

        session.bridge.detachScripts(from: PapyrusWorldFixture.cell)

        #expect(session.world.instancesByKey.isEmpty)
    }
}
