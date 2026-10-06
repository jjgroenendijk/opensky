// The Papyrus table over synthetic tables: every value kind, arrays, both id widths,
// and stacks counted and named.

import FormatsTesting
import Foundation
@testable import OpenSkyFormatsESS
import TagsTesting
import Testing

@Suite(.tags(.parser))
struct ESSPapyrusTests {
    private static func fixture(idWidth: Int = 4) -> ESSPapyrusFixture {
        var fixture = ESSPapyrusFixture()
        fixture.idWidth = idWidth
        fixture.scripts = [ESSPapyrusFixtureScript(
            name: "MQ101Script", parent: "Quest",
            members: [("::Count_var", "Int"), ("::Name_var", "String")]
        )]
        fixture.instances = [ESSPapyrusFixtureInstance(
            id: 0x10, script: "MQ101Script", form: (kind: 1, value: 0x3372B),
            variables: [
                .null, .object(type: "Actor", id: 0x11), .string("Hadvar"), .integer(-4),
                .float(2.5), .boolean(true), .array(kind: 11, type: "Actor", id: 0x20),
                .array(kind: 13, type: nil, id: 0x21)
            ]
        )]
        fixture.arrays = [
            ESSPapyrusFixtureArray(
                id: 0x20, element: 1, objectType: "Actor", values: [.object(
                    type: "Actor",
                    id: 0x11
                )]
            ),
            ESSPapyrusFixtureArray(id: 0x21, element: 3, values: [.integer(1), .integer(2)])
        ]
        return fixture
    }

    @Test func decodesEveryValueKind() throws {
        var fixture = Self.fixture()
        let papyrus = try ESSPapyrus(data: fixture.build())
        #expect(papyrus.idWidth == 4)
        #expect(papyrus.scripts.first?.members.map(\.name) == ["::Count_var", "::Name_var"])
        #expect(papyrus.scripts.first?.parent == "Quest")
        let instance = try #require(papyrus.instances.first)
        #expect(instance.scriptName == "MQ101Script")
        #expect(instance.form == ESSRefID(kind: .default, value: 0x3372B))
        #expect(instance.variables == [
            .null, .object(type: "Actor", id: 0x11), .string("Hadvar"), .integer(-4),
            .float(2.5), .boolean(true), .array(element: .object, type: "Actor", id: 0x20),
            .array(element: .integer, type: nil, id: 0x21)
        ])
        #expect(papyrus.arrays.map(\.length) == [1, 2])
        #expect(papyrus.arrays[1].elements == [.integer(1), .integer(2)])
        #expect(papyrus.instances(on: instance.form).count == 1)
    }

    @Test func fallsBackToWideIDs() throws {
        var fixture = Self.fixture(idWidth: 8)
        let papyrus = try ESSPapyrus(data: fixture.build())
        #expect(papyrus.idWidth == 8)
        #expect(papyrus.instances.first?.variables.count == 8)
    }

    @Test func countsAndNamesStacks() throws {
        var fixture = Self.fixture()
        fixture.activeStacks = [(id: 7, script: "MQ101Script")]
        fixture.suspendedStacks = [(id: 9, script: "DefaultOnEnter")]
        let papyrus = try ESSPapyrus(data: fixture.build())
        #expect(papyrus.stackStatus == .complete)
        #expect(papyrus.activeScripts.map(\.id) == [7])
        #expect(papyrus.activeScriptNames[7] == "MQ101Script")
        #expect(papyrus.suspendedStacks == [ESSPapyrusSuspendedStack(
            id: 9,
            scriptName: "DefaultOnEnter"
        )])
    }

    @Test func brokenStackDataKeepsTheVariables() throws {
        var fixture = Self.fixture()
        fixture.activeStacks = [(id: 7, script: "MQ101Script")]
        let data = fixture.build()
        let papyrus = try ESSPapyrus(data: data.prefix(data.count - 12))
        #expect(papyrus.instances.first?.variables.count == 8)
        #expect(!papyrus.stackStatus.isComplete)
    }

    @Test func badStringReferenceThrows() {
        var data = Data([4, 0, 0, 0])
        data.append(contentsOf: [1, 0, 0, 0, 5, 0, 5, 0, 0, 0, 0, 0])
        #expect(throws: ESSError.self) { try ESSPapyrus(data: data) }
    }
}
