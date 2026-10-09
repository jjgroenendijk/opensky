// `FormList.GetSize` and `GetAt` over a synthetic FLST.

import FormatsTesting
import Foundation
@testable import OpenSkyFormatsESM
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
