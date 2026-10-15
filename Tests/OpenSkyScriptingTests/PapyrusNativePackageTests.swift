// `Package.GetTemplate` reads the package record's `PKCU` template.

import Foundation
import OpenSkyFormatsESM
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
import Testing

@MainActor
struct PapyrusNativePackageTests {
    @Test func getTemplateReadsThePackageRecord() throws {
        let fixture = try PapyrusNativeReferenceFixture.make()
        let doorID = PapyrusNativeReferenceFixture.doorID
        let template = { (package: UInt32) in
            fixture.registry.invoke(PapyrusWorldFixture.methodCall(
                "Package", "GetTemplate", receiver: fixture.handle(package),
                returnType: .object("Package")
            ))
        }
        guard case .failed = template(0x100) else {
            Issue.record("GetTemplate answered without the package records")
            return
        }
        fixture.session.bridge.packageTemplate = { $0 == FormID(0x100) ? FormID(doorID) : nil }
        #expect(template(0x100) == .returned(.object(fixture.handle(doorID))))
        #expect(template(doorID) == .returned(.none))
    }
}
