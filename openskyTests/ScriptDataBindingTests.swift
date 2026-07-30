import Foundation
@testable import opensky
import Testing

@Suite("VMAD Papyrus binding")
struct ScriptDataBindingTests {
    @Test("uses decoded PEX backing names and resolved world handles")
    func bindsAutomaticProperties() throws {
        let runtime = makeRuntime()
        let attached = try script(properties: [
            .init("Target", .object(VMADFixture.object(0x0000_1234))),
            .init("Count", .integer(42)),
            .init("Names", .strings(["A", "B"]))
        ])
        let key = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x1234)
        let worldHandle = PapyrusObjectHandle(900)

        let bound = try attached.makeInstance(
            in: runtime,
            handle: PapyrusObjectHandle(7),
            formIDResolver: resolver
        ) { reference in
            reference == key ? worldHandle : nil
        }

        let instance = try #require(runtime.instance(for: bound.handle))
        #expect(instance.value(named: "::opaque_backing_17", declaredBy: "BoundScript")
            == .object(worldHandle))
        #expect(instance.value(named: "::count_storage", declaredBy: "BoundScript")
            == .integer(42))
        let names = instance.value(named: "::names_storage", declaredBy: "BoundScript")
        guard case let .array(array) = names else {
            Issue.record("Names did not bind as a Papyrus array")
            return
        }
        #expect(array.elementType == .string)
        #expect(array.elements == [.string("A"), .string("B")])
        #expect(bound.binding.resolvedReferences == [key])
        #expect(bound.binding.skipped.total == 0)
    }

    @Test("unresolved and alias objects preserve compiler defaults")
    func preservesDefaultsForSkippedObjects() throws {
        for (object, expectedReason) in [
            (VMADFixture.object(0x0000_1234), "unresolved object reference"),
            (VMADFixture.object(0x0000_1234, alias: 3), "quest-alias object")
        ] {
            let runtime = makeRuntime()
            let attached = try script(properties: [.init("Target", .object(object))])
            let bound = try attached.makeInstance(
                in: runtime,
                formIDResolver: resolver
            ) { _ in nil }
            let instance = try #require(runtime.instance(for: bound.handle))
            #expect(instance.value(
                named: "::opaque_backing_17",
                declaredBy: "BoundScript"
            ) == PapyrusValue.none)
            #expect(bound.binding.initialValues.isEmpty)
            #expect(bound.binding.skipped.ranked.first?.name == expectedReason)
        }
    }

    @Test("removed and unknown VMAD properties preserve PEX defaults")
    func preservesDefaultsForRemovedAndMissingProperties() throws {
        let runtime = makeRuntime()
        let attached = try script(properties: [
            .init("Count", .integer(99), flags: 2),
            .init("NoSuchProperty", .integer(8))
        ])
        let bound = try attached.makeInstance(
            in: runtime,
            formIDResolver: resolver
        ) { _ in nil }
        let instance = try #require(runtime.instance(for: bound.handle))
        #expect(instance.value(named: "::count_storage", declaredBy: "BoundScript")
            == .integer(5))
        #expect(bound.binding.initialValues.isEmpty)
        #expect(bound.binding.skipped.total == 2)
        #expect(bound.binding.skipped.ranked.map(\.name) == [
            "property missing from PEX",
            "removed property"
        ])
    }

    @Test("removed script attachments cannot create instances")
    func rejectsRemovedScript() throws {
        let runtime = makeRuntime()
        let attached = try script(properties: [], flags: 2)
        #expect(throws: ScriptBindingError.removedScript("BoundScript")) {
            _ = try attached.makeInstance(
                in: runtime,
                formIDResolver: resolver
            ) { _ in nil }
        }
    }

    private var resolver: FormIDResolver {
        FormIDResolver(pluginName: "Test.esp", masters: ["Skyrim.esm"])
    }

    private func script(
        properties: [VMADFixture.Property],
        flags: UInt8 = 0
    ) throws -> AttachedScript {
        var data = ScriptData()
        _ = try data.decode(field: ESMField(
            type: "VMAD",
            data: VMADFixture.payload(scripts: [
                .init("BoundScript", flags: flags, properties: properties)
            ])
        ))
        return try #require(data.scripts.first)
    }

    private func makeRuntime() -> PapyrusRuntime {
        let variables = [
            PexVariable(
                name: "::opaque_backing_17",
                typeName: "ObjectReference",
                userFlags: 0,
                initialValue: .null
            ),
            PexVariable(
                name: "::count_storage",
                typeName: "Int",
                userFlags: 0,
                initialValue: .integer(5)
            ),
            PexVariable(
                name: "::names_storage",
                typeName: "String[]",
                userFlags: 0,
                initialValue: .null
            )
        ]
        let properties = [
            automaticProperty("Target", type: "ObjectReference", backing: "::opaque_backing_17"),
            automaticProperty("Count", type: "Int", backing: "::count_storage"),
            automaticProperty("Names", type: "String[]", backing: "::names_storage")
        ]
        let object = PexFixture.runtimeObject(
            name: "BoundScript",
            variables: variables,
            properties: properties,
            states: []
        )
        return PapyrusRuntime(files: [PexFixture.runtimeFile(objects: [object])])
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
