// Scene fragments under the Papyrus world runtime: a fragment without a script name queues
// nothing.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import Testing

@MainActor
struct PapyrusSceneFragmentTests {
    @Test func aFragmentWithoutAScriptNameQueuesNothing() throws {
        let session = PapyrusWorldFixture.session(objects: [], entries: [])
        PapyrusWorldFixture.drain(session.world)
        let scene = try Scene(record: ESMFixture.record("SCEN", formID: 0x3000, fields: []))
        let key = ReferenceKey.plugin(name: PapyrusWorldFixture.pluginName, objectID: 0x3000)

        #expect(!session.bridge.runSceneFragment(
            of: scene, key: key, scriptName: "", functionName: "Fragment_0"
        ))
        #expect(session.world.eventQueue.isEmpty)
    }
}
