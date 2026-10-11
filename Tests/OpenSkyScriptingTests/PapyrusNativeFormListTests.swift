// `FormList.GetSize` and `GetAt` over a synthetic FLST, and `Form.HasKeyword` over a
// synthetic KWDA.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
@testable import OpenSkyScriptingInterface
import Testing

@MainActor
struct PapyrusNativeFormListTests {
    private typealias Fixture = PapyrusNativeReferenceFixture
    private static let listID: UInt32 = 0x0000_0EEE

    @Test func sizeAndEntriesReadThePluginList() throws {
        let fixture = try Fixture.make()
        let file = try KeywordFixture.plugin(formLists: [
            FormListFixture.recordBytes(formID: Self.listID, entries: [Fixture.leverID, 0])
        ])
        fixture.session.bridge.formListStore = FormListStore(plugins: [("Skyrim.esm", file)])
        let list = fixture.handle(Self.listID)

        #expect(call(fixture, "GetSize", on: list, returnType: .integer) == .returned(.integer(2)))
        let first = call(fixture, "GetAt", on: list, [.integer(0)], returnType: .object("Form"))
        #expect(first == .returned(.object(fixture.receiver)))
        #expect(call(fixture, "GetAt", on: list, [.integer(1)]) == .returned(.none))
        #expect(call(fixture, "GetAt", on: list, [.integer(9)]) == .returned(.none))
    }

    @Test func withoutFormListDataTheyFail() throws {
        let fixture = try Fixture.make()
        let result = call(fixture, "GetSize", on: fixture.handle(Self.listID), returnType: .integer)
        guard case .failed = result else {
            Issue.record("GetSize without FLST data should fail: \(result)")
            return
        }
    }

    @Test func hasKeywordReadsTheFormsKeywordList() throws {
        let fixture = try Fixture.make()
        let misc = ESMFixture.field("KSIZ", ESMFixture.u32(1))
            + ESMFixture.field("KWDA", ESMFixture.u32(Fixture.keywordID))
        let file = try ESMFile(data: ESMFixture.tes4()
            + ESMFixture.topGroup("KYWD", contents: KeywordFixture.recordBytes(
                formID: Fixture.keywordID, editorID: "isExecutioner"
            ) + KeywordFixture.recordBytes(formID: Fixture.otherKeywordID, editorID: "Other"))
            + ESMFixture.topGroup("MISC", contents: ESMFixture.record(
                "MISC", formID: Self.listID, data: misc
            )))
        fixture.session.bridge.keywordStore = KeywordStore(index: RecordIndex(
            plugins: [("Skyrim.esm", file)], recordTypes: RecordIndex.referenceRecordTypes
        ))
        let form = fixture.handle(Self.listID)
        for (keyword, expected) in [(Fixture.keywordID, true), (Fixture.otherKeywordID, false)] {
            let result = fixture.registry.invoke(PapyrusWorldFixture.methodCall(
                "Form", "HasKeyword", receiver: form,
                arguments: [.object(fixture.handle(keyword))], returnType: .boolean
            ))
            #expect(result == .returned(.boolean(expected)))
        }
    }

    private func call(
        _ fixture: Fixture,
        _ functionName: String,
        on list: PapyrusObjectHandle,
        _ arguments: [PapyrusValue] = [],
        returnType: PapyrusType = .none
    ) -> PapyrusNativeResult {
        fixture.registry.invoke(PapyrusWorldFixture.methodCall(
            "FormList", functionName, receiver: list, arguments: arguments, returnType: returnType
        ))
    }
}
