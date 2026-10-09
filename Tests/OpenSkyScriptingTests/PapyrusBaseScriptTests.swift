@testable import FormatsTesting
import Foundation
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
import OpenSkyWorldState
import Testing

@MainActor
struct PapyrusBaseScriptTests {
    @Test("a reference runs its base object's scripts beside its own")
    func baseScriptsAttach() throws {
        let world = PapyrusWorldFixture.worldRuntime(
            objects: [
                PapyrusWorldFixture.fullEventScript("AScript"),
                PapyrusWorldFixture.fullEventScript("BScript")
            ],
            nativeDispatch: PapyrusWorldProbeDispatch()
        )
        let own = try PapyrusWorldFixture.referenceEntry(
            objectID: 1, scripts: [.init("BScript", properties: [])]
        )
        let base = try PapyrusWorldFixture.referenceEntry(
            objectID: 2, scripts: [.init("AScript", properties: [])]
        )
        let entry = RuntimeReferenceEntry(
            key: own.key, formID: own.formID, isPersistent: false, record: own.record,
            baseScripts: base.scripts
        )
        world.attach(
            cell: PapyrusWorldFixture.cell,
            references: PapyrusWorldFixture.index([entry]),
            formIDResolver: PapyrusWorldFixture.resolver,
            firstIntegration: true
        )
        let names = world.instanceKeys(on: entry.key).map(\.scriptName)
        #expect(names == ["ascript", "bscript"])
    }
}
