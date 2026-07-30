// Save-state seam and identity ordering for `PapyrusWorldRuntime`
// (issue #171): deterministic `instanceStates()`, tolerant restore, and the
// `PapyrusInstanceKey` total order later stages serialize under.

import Foundation
@testable import opensky
import Testing

@MainActor
struct PapyrusWorldRuntimeTests {
    @Test("instance keys order by reference first, then script name")
    func instanceKeyOrdering() {
        let low = PapyrusWorldFixture.key(objectID: 1, script: "ZScript")
        let high = PapyrusWorldFixture.key(objectID: 2, script: "AScript")
        let sibling = PapyrusWorldFixture.key(objectID: 1, script: "AScript")
        #expect(low < high)
        #expect(sibling < low)
        #expect(PapyrusWorldFixture.key(objectID: 1, script: "MixedCase")
            == PapyrusWorldFixture.key(objectID: 1, script: "mixedcase"))
    }

    @Test("instance states round-trip: state name, variables, fired set")
    func instanceStatesRoundTrip() throws {
        let probe = PapyrusWorldProbeDispatch()
        let world = try makeWorld(probe: probe)
        PapyrusWorldFixture.drain(world)
        let key = PapyrusWorldFixture.key(objectID: 1, script: "StatefulScript")
        let handle = try #require(world.instancesByKey[key])
        let instance = try #require(world.runtime.instance(for: handle))
        instance.activeState = "Ready"
        #expect(instance.setValue(.integer(11), named: "count", declaredBy: "StatefulScript"))
        #expect(instance.setValue(
            .string("hello"), named: "label", declaredBy: "StatefulScript"
        ))

        let states = world.instanceStates()
        #expect(states.count == 1)
        let state = try #require(states.first)
        #expect(state.key == key)
        #expect(state.activeState == "Ready")
        #expect(state.hasFiredOnInit)
        // Sorted by (declaringScript, name); both keys are lowercased.
        #expect(state.variables.map(\.name) == ["count", "label", "opaque", "values"])

        // Restore into a fresh runtime that has attached no cell yet: the
        // instance is created from the script library on demand.
        let restoredProbe = PapyrusWorldProbeDispatch()
        let restored = try makeWorld(probe: restoredProbe, attach: false)
        restored.restore(instanceStates: states)
        #expect(restored.instanceStates() == states)

        // The fired set survives: attaching the same reference later must
        // not refire OnInit.
        try restored.attach(
            cell: PapyrusWorldFixture.cell,
            references: references(),
            formIDResolver: PapyrusWorldFixture.resolver,
            firstIntegration: true
        )
        PapyrusWorldFixture.drain(restored)
        #expect(!restoredProbe.notes.contains("stateful.oninit"))
    }

    @Test("object and array values persist as .none")
    func objectAndArrayValuesAreNotPersistable() throws {
        let world = try makeWorld(probe: PapyrusWorldProbeDispatch())
        PapyrusWorldFixture.drain(world)
        let key = PapyrusWorldFixture.key(objectID: 1, script: "StatefulScript")
        let handle = try #require(world.instancesByKey[key])
        let instance = try #require(world.runtime.instance(for: handle))
        #expect(instance.setValue(
            .object(handle), named: "opaque", declaredBy: "StatefulScript"
        ))
        #expect(instance.setValue(
            .array(PapyrusArray(elementType: .integer, elements: [.integer(3)])),
            named: "values",
            declaredBy: "StatefulScript"
        ))

        let state = try #require(world.instanceStates().first)
        let byName = Dictionary(
            uniqueKeysWithValues: state.variables.map { ($0.name, $0.value) }
        )
        #expect(byName["opaque"] == PapyrusValue.none)
        #expect(byName["values"] == PapyrusValue.none)
    }

    @Test("restore skips and counts unknown scripts and variables")
    func restoreIsTolerant() throws {
        let world = try makeWorld(probe: PapyrusWorldProbeDispatch(), attach: false)
        let unknownScript = PapyrusInstanceState(
            key: PapyrusWorldFixture.key(objectID: 9, script: "NeverCompiled"),
            activeState: "",
            variables: [],
            hasFiredOnInit: true
        )
        let unknownVariable = PapyrusInstanceState(
            key: PapyrusWorldFixture.key(objectID: 1, script: "StatefulScript"),
            activeState: "",
            variables: [PapyrusVariableState(
                declaringScript: "StatefulScript",
                name: "renamedSinceSave",
                value: .integer(1)
            )],
            hasFiredOnInit: true
        )
        world.restore(instanceStates: [unknownScript, unknownVariable])
        #expect(world.skips.counts[.unknownSaveScript] == 1)
        #expect(world.skips.counts[.unknownSaveVariable] == 1)
        #expect(world.instancesByKey.count == 1)
        #expect(world.firedOnInit.contains(unknownVariable.key))
    }

    private func references() throws -> RuntimeReferenceIndex {
        try PapyrusWorldFixture.index([
            PapyrusWorldFixture.referenceEntry(
                objectID: 1, scripts: [.init("StatefulScript", properties: [])]
            )
        ])
    }

    /// One "StatefulScript" instance with int, string, object, and array
    /// variables plus a probing `OnInit`.
    private func makeWorld(
        probe: PapyrusWorldProbeDispatch,
        attach: Bool = true
    ) throws -> PapyrusWorldRuntime {
        let variables = [
            PexVariable(name: "count", typeName: "Int", userFlags: 0, initialValue: .integer(0)),
            PexVariable(name: "label", typeName: "String", userFlags: 0, initialValue: .null),
            PexVariable(
                name: "opaque", typeName: "StatefulScript", userFlags: 0, initialValue: .null
            ),
            PexVariable(name: "values", typeName: "Int[]", userFlags: 0, initialValue: .null)
        ]
        let script = PapyrusWorldFixture.eventScript(
            "StatefulScript",
            events: [("OnInit", PapyrusWorldFixture.probeBody(note: "stateful.oninit"))],
            variables: variables
        )
        let world = PapyrusWorldFixture.worldRuntime(
            objects: [script], nativeDispatch: probe
        )
        if attach {
            try world.attach(
                cell: PapyrusWorldFixture.cell,
                references: references(),
                formIDResolver: PapyrusWorldFixture.resolver,
                firstIntegration: true
            )
        }
        return world
    }
}
