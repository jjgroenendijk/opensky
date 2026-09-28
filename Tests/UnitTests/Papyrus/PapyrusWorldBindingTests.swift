// VMAD property binding and attach-skip accounting for
// `PapyrusWorldRuntime` (issue #171), split from the lifecycle suite for the
// type-body lint cap.

import Foundation
@testable import opensky
import Testing

@MainActor
struct PapyrusWorldBindingTests {
    @Test("VMAD properties bind, intra-cell object properties resolve")
    func vmadPropertiesBindAcrossTheCell() throws {
        let holder = PapyrusWorldFixture.eventScript(
            "HolderScript",
            events: [],
            variables: [
                PexVariable(
                    name: "::count_var", typeName: "Int",
                    userFlags: 0, initialValue: .integer(1)
                ),
                PexVariable(
                    name: "::target_var", typeName: "TargetScript",
                    userFlags: 0, initialValue: .null
                )
            ],
            properties: [
                automaticProperty("Count", type: "Int", backing: "::count_var"),
                automaticProperty("Target", type: "TargetScript", backing: "::target_var")
            ]
        )
        let target = PapyrusWorldFixture.eventScript("TargetScript", events: [])
        let world = PapyrusWorldFixture.worldRuntime(
            objects: [holder, target],
            nativeDispatch: PapyrusWorldProbeDispatch()
        )
        let references = try PapyrusWorldFixture.index([
            PapyrusWorldFixture.referenceEntry(objectID: 1, scripts: [
                .init("HolderScript", properties: [
                    .init("Count", .integer(42)),
                    .init("Target", .object(VMADFixture.object(2)))
                ])
            ]),
            PapyrusWorldFixture.referenceEntry(
                objectID: 2, scripts: [.init("TargetScript", properties: [])]
            )
        ])
        world.attach(
            cell: PapyrusWorldFixture.cell,
            references: references,
            formIDResolver: PapyrusWorldFixture.resolver,
            firstIntegration: true
        )
        let holderHandle = try #require(world.instancesByKey[
            PapyrusWorldFixture.key(objectID: 1, script: "HolderScript")
        ])
        let targetHandle = try #require(world.instancesByKey[
            PapyrusWorldFixture.key(objectID: 2, script: "TargetScript")
        ])
        let instance = try #require(world.runtime.instance(for: holderHandle))
        #expect(instance.value(named: "::count_var", declaredBy: "HolderScript")
            == .integer(42))
        #expect(instance.value(named: "::target_var", declaredBy: "HolderScript")
            == .object(targetHandle))
    }

    @Test("removed and library-missing scripts are counted, never faults")
    func skipsAreCounted() throws {
        let world = PapyrusWorldFixture.worldRuntime(
            objects: [PapyrusWorldFixture.fullEventScript("AScript")],
            nativeDispatch: PapyrusWorldProbeDispatch()
        )
        let references = try PapyrusWorldFixture.index([
            PapyrusWorldFixture.referenceEntry(objectID: 1, scripts: [
                .init("AScript", flags: 0x02, properties: []), // removed
                .init("NotInLibrary", properties: [])
            ])
        ])
        world.attach(
            cell: PapyrusWorldFixture.cell,
            references: references,
            formIDResolver: PapyrusWorldFixture.resolver,
            firstIntegration: true
        )
        #expect(world.instancesByKey.isEmpty)
        #expect(world.skips.counts[.removedScript] == 1)
        #expect(world.skips.counts[.missingScript] == 1)
    }

    private func automaticProperty(
        _ name: String,
        type: String,
        backing: String
    ) -> PexProperty {
        PexProperty(
            name: name,
            typeName: type,
            documentation: "",
            userFlags: 0,
            flags: [.readable, .writable, .automatic],
            automaticVariableName: backing,
            readHandler: nil,
            writeHandler: nil
        )
    }
}
