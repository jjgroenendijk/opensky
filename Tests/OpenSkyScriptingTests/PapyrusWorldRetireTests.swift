@testable import FormatsTesting
import Foundation
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
import Testing

@MainActor
struct PapyrusWorldRetireTests {
    @Test("a waiting call of a retired instance never resumes")
    func aRetiredWaitNeverResumes() throws {
        let probe = PapyrusWorldProbeDispatch()
        let waiter = PapyrusWorldFixture.eventScript("WaiterScript", events: [
            ("OnLoad", PapyrusWorldFixture.probeBody(note: "waiter.done", waitSeconds: 0.1))
        ])
        let world = PapyrusWorldFixture.worldRuntime(objects: [waiter], nativeDispatch: probe)
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
        world.eventQueue = [PapyrusScriptEvent(
            target: PapyrusWorldFixture.key(objectID: 1, script: "WaiterScript"),
            functionName: "OnLoad",
            arguments: []
        )]
        #expect(world.stepFixed().dispatched == 1)
        #expect(world.scheduler.pendingCount == 1)

        world.detach(cell: PapyrusWorldFixture.cell)
        #expect(world.scheduler.pendingCount == 0)
        for _ in 0 ..< 10 {
            #expect(world.stepFixed().resumed == 0)
        }
        #expect(probe.notes.isEmpty)
    }
}
