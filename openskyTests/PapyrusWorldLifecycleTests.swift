// Cell attach/detach lifecycle for `PapyrusWorldRuntime` (issue #171):
// deterministic instantiation order, event order, rebuild reconciliation,
// retirement, and persistent-instance survival.

import Foundation
@testable import opensky
import Testing

@MainActor
struct PapyrusWorldLifecycleTests {
    @Test("first integration creates instances and events in sorted order")
    func firstIntegrationOrder() throws {
        let probe = PapyrusWorldProbeDispatch()
        let world = PapyrusWorldFixture.worldRuntime(
            objects: [
                PapyrusWorldFixture.fullEventScript("AScript"),
                PapyrusWorldFixture.fullEventScript("BScript")
            ],
            nativeDispatch: probe
        )
        // Reference 2 carries AScript, reference 1 carries BScript: sorted
        // entry order (by reference) must win over script name.
        let references = try PapyrusWorldFixture.index([
            PapyrusWorldFixture.referenceEntry(
                objectID: 2,
                scripts: [.init("AScript", properties: [])]
            ),
            PapyrusWorldFixture.referenceEntry(
                objectID: 1,
                scripts: [.init("BScript", properties: [])]
            )
        ])
        world.attach(
            cell: PapyrusWorldFixture.cell,
            references: references,
            formIDResolver: PapyrusWorldFixture.resolver,
            firstIntegration: true
        )
        #expect(world.instancesByKey.count == 2)
        #expect(probe.notes.isEmpty) // enqueued, never dispatched inline

        PapyrusWorldFixture.drain(world)
        #expect(probe.notes == [
            "bscript.oninit", "bscript.oncellattach", "bscript.onload",
            "ascript.oninit", "ascript.oncellattach", "ascript.onload"
        ])
    }

    @Test("a rebuild keeps instances and enqueues nothing")
    func rebuildIsSilent() throws {
        let probe = PapyrusWorldProbeDispatch()
        let world = PapyrusWorldFixture.worldRuntime(
            objects: [PapyrusWorldFixture.fullEventScript("AScript")],
            nativeDispatch: probe
        )
        let references = try PapyrusWorldFixture.index([
            PapyrusWorldFixture.referenceEntry(
                objectID: 1,
                scripts: [.init("AScript", properties: [])]
            )
        ])
        world.attach(
            cell: PapyrusWorldFixture.cell,
            references: references,
            formIDResolver: PapyrusWorldFixture.resolver,
            firstIntegration: true
        )
        PapyrusWorldFixture.drain(world)
        let notesAfterFirst = probe.notes
        let handle = world.instancesByKey[
            PapyrusWorldFixture.key(objectID: 1, script: "AScript")
        ]

        world.attach(
            cell: PapyrusWorldFixture.cell,
            references: references,
            formIDResolver: PapyrusWorldFixture.resolver,
            firstIntegration: false
        )
        PapyrusWorldFixture.drain(world)
        #expect(probe.notes == notesAfterFirst)
        #expect(world.instancesByKey.count == 1)
        #expect(world.instancesByKey[
            PapyrusWorldFixture.key(objectID: 1, script: "AScript")
        ] == handle)
    }

    @Test("a reference newly appearing in a rebuilt cell gets only OnInit")
    func rebuildNewReferenceGetsOnInitOnly() throws {
        let probe = PapyrusWorldProbeDispatch()
        let world = PapyrusWorldFixture.worldRuntime(
            objects: [
                PapyrusWorldFixture.fullEventScript("AScript"),
                PapyrusWorldFixture.fullEventScript("CScript")
            ],
            nativeDispatch: probe
        )
        let first = try PapyrusWorldFixture.referenceEntry(
            objectID: 1, scripts: [.init("AScript", properties: [])]
        )
        world.attach(
            cell: PapyrusWorldFixture.cell,
            references: PapyrusWorldFixture.index([first]),
            formIDResolver: PapyrusWorldFixture.resolver,
            firstIntegration: true
        )
        PapyrusWorldFixture.drain(world)
        let notesAfterFirst = probe.notes

        let rebuilt = try PapyrusWorldFixture.index([
            first,
            PapyrusWorldFixture.referenceEntry(
                objectID: 2,
                scripts: [.init("CScript", properties: [])]
            )
        ])
        world.attach(
            cell: PapyrusWorldFixture.cell,
            references: rebuilt,
            formIDResolver: PapyrusWorldFixture.resolver,
            firstIntegration: false
        )
        PapyrusWorldFixture.drain(world)
        #expect(probe.notes == notesAfterFirst + ["cscript.oninit"])
        #expect(world.instancesByKey.count == 2)
    }

    @Test("detach retires instances and queued events; OnInit never refires")
    func detachRetires() throws {
        let probe = PapyrusWorldProbeDispatch()
        let world = PapyrusWorldFixture.worldRuntime(
            objects: [PapyrusWorldFixture.fullEventScript("AScript")],
            nativeDispatch: probe
        )
        let references = try PapyrusWorldFixture.index([
            PapyrusWorldFixture.referenceEntry(
                objectID: 1,
                scripts: [.init("AScript", properties: [])]
            )
        ])
        world.attach(
            cell: PapyrusWorldFixture.cell,
            references: references,
            formIDResolver: PapyrusWorldFixture.resolver,
            firstIntegration: true
        )
        PapyrusWorldFixture.drain(world)
        #expect(probe.notes.contains("ascript.oninit"))

        // Queue more events, then detach before they run: both the instance
        // and its queued events must go.
        world.attach(
            cell: PapyrusWorldFixture.cell,
            references: references,
            formIDResolver: PapyrusWorldFixture.resolver,
            firstIntegration: true
        )
        world.detach(cell: PapyrusWorldFixture.cell)
        #expect(world.instancesByKey.isEmpty)
        #expect(world.eventQueue.isEmpty)
        #expect(world.runtime.instances.isEmpty)

        // Walking back in re-creates the instance; the persisted fired set
        // means OnInit stays fired for that reference forever.
        let notesBefore = probe.notes.count
        world.attach(
            cell: PapyrusWorldFixture.cell,
            references: references,
            formIDResolver: PapyrusWorldFixture.resolver,
            firstIntegration: true
        )
        PapyrusWorldFixture.drain(world)
        let reattachNotes = Array(probe.notes.dropFirst(notesBefore))
        #expect(reattachNotes == ["ascript.oncellattach", "ascript.onload"])
    }

    @Test("a persistent instance survives detach with its variables intact")
    func persistentInstanceSurvivesDetach() throws {
        let probe = PapyrusWorldProbeDispatch()
        let counter = PexVariable(
            name: "counter", typeName: "Int", userFlags: 0, initialValue: .integer(0)
        )
        let script = PapyrusWorldFixture.eventScript(
            "KeeperScript",
            events: [
                ("OnInit", PapyrusWorldFixture.probeBody(note: "keeper.oninit")),
                ("OnCellAttach", PapyrusWorldFixture.probeBody(note: "keeper.oncellattach"))
            ],
            variables: [counter]
        )
        let world = PapyrusWorldFixture.worldRuntime(
            objects: [script], nativeDispatch: probe
        )
        let references = try PapyrusWorldFixture.index([
            PapyrusWorldFixture.referenceEntry(
                objectID: 7,
                scripts: [.init("KeeperScript", properties: [])],
                isPersistent: true
            )
        ])
        world.attach(
            cell: PapyrusWorldFixture.cell,
            references: references,
            formIDResolver: PapyrusWorldFixture.resolver,
            firstIntegration: true
        )
        PapyrusWorldFixture.drain(world)
        let key = PapyrusWorldFixture.key(objectID: 7, script: "KeeperScript")
        let handle = try #require(world.instancesByKey[key])
        let instance = try #require(world.runtime.instance(for: handle))
        #expect(instance.setValue(.integer(9), named: "counter", declaredBy: "KeeperScript"))

        world.detach(cell: PapyrusWorldFixture.cell)
        #expect(world.instancesByKey[key] == handle)

        let notesBefore = probe.notes.count
        world.attach(
            cell: PapyrusWorldFixture.cell,
            references: references,
            formIDResolver: PapyrusWorldFixture.resolver,
            firstIntegration: true
        )
        PapyrusWorldFixture.drain(world)
        #expect(Array(probe.notes.dropFirst(notesBefore)) == ["keeper.oncellattach"])
        let survivor = try #require(world.runtime.instance(for: handle))
        #expect(survivor.value(named: "counter", declaredBy: "KeeperScript") == .integer(9))
    }
}
