// The reference-to-instances index answers what a filter over every live instance
// would, in key order, through attach and retire.

import Foundation
import OpenSkyFormatsESM
@testable import OpenSkyFormatsTesting
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
import OpenSkyWorldState
import Testing

@MainActor
struct PapyrusInstanceIndexTests {
    private static func filtered(
        _ world: PapyrusWorldRuntime, _ reference: ReferenceKey
    ) -> [PapyrusInstanceKey] {
        world.instancesByKey.keys.filter { $0.reference == reference }.sorted()
    }

    @Test func indexMatchesAFilterOverEveryInstance() throws {
        let world = PapyrusWorldFixture.worldRuntime(
            objects: ["CScript", "AScript", "BScript"].map(PapyrusWorldFixture.fullEventScript),
            nativeDispatch: PapyrusWorldProbeDispatch()
        )
        let first = try PapyrusWorldFixture.referenceEntry(
            objectID: 1, scripts: [
                .init("CScript", properties: []),
                .init("AScript", properties: [])
            ]
        )
        let second = try PapyrusWorldFixture.referenceEntry(
            objectID: 2, scripts: [.init("BScript", properties: [])]
        )
        world.attach(
            cell: PapyrusWorldFixture.cell,
            references: PapyrusWorldFixture.index([first, second]),
            formIDResolver: PapyrusWorldFixture.resolver,
            firstIntegration: true
        )
        for reference in [first.key, second.key] {
            #expect(world.instanceKeys(on: reference) == Self.filtered(world, reference))
        }
        #expect(world.instanceKeys(on: first.key).map(\.scriptName) == ["ascript", "cscript"])

        world.retire(PapyrusWorldFixture.key(objectID: 1, script: "AScript"))
        #expect(world.instanceKeys(on: first.key).map(\.scriptName) == ["cscript"])
        world.retire(PapyrusWorldFixture.key(objectID: 2, script: "BScript"))
        #expect(world.instanceKeys(on: second.key).isEmpty)
        #expect(world.instanceKeys(on: first.key) == Self.filtered(world, first.key))
    }
}
