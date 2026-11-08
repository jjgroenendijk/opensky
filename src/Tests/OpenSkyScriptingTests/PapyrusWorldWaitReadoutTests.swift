// What `game state` reads of a reference's scripts: the calls they wait in and
// their live variables.

import Foundation
@testable import OpenSkyFormatsPEX
@testable import OpenSkyFormatsTesting
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
import Testing

@MainActor
struct PapyrusWorldWaitReadoutTests {
    @Test func aWaitingScriptShowsItsCallAndVariables() throws {
        let waiter = PapyrusWorldFixture.eventScript(
            "WaiterScript",
            events: [
                ("OnLoad", PapyrusWorldFixture.probeBody(note: "waiter.done", waitSeconds: 0.1))
            ],
            variables: [
                PexVariable(name: "count", typeName: "Int", userFlags: 0, initialValue: .integer(3))
            ]
        )
        let world = PapyrusWorldFixture.worldRuntime(
            objects: [waiter], nativeDispatch: PapyrusWorldProbeDispatch()
        )
        try world.attach(
            cell: PapyrusWorldFixture.cell,
            references: PapyrusWorldFixture.index([
                PapyrusWorldFixture.referenceEntry(
                    objectID: 1, scripts: [.init("WaiterScript", properties: [])]
                )
            ]),
            formIDResolver: PapyrusWorldFixture.resolver,
            firstIntegration: false
        )
        let target = PapyrusWorldFixture.key(objectID: 1, script: "WaiterScript")
        world.eventQueue = [PapyrusScriptEvent(
            target: target,
            functionName: "OnLoad",
            arguments: []
        )]
        #expect(world.stepFixed().dispatched == 1)

        let waits = world.waits(on: target.reference)
        #expect(waits.map(\.script) == [target.scriptName])
        #expect(waits.map { $0.native.lowercased() } == ["utility.wait"])
        let instances = world.instances(on: target.reference)
        #expect(instances.map(\.script) == [target.scriptName])
        #expect(instances.first?.variables.count == 1)
        #expect(instances.first?.variables.first?.hasPrefix("count = ") == true)
        let other = PapyrusWorldFixture.key(objectID: 2, script: "WaiterScript").reference
        #expect(world.waits(on: other).isEmpty)
        #expect(world.instances(on: other).isEmpty)
    }
}
