// `GetMass` reads the Havok body mass, and answers 0 for a reference Havok does not move.

import Foundation
import OpenSkyFormatsESM
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
import Testing

@MainActor
struct PapyrusNativeMassTests {
    @Test func getMassReadsTheHavokBody() throws {
        let fixture = try PapyrusNativeReferenceFixture.make()
        guard case .failed = fixture.call("GetMass", returnType: .float) else {
            Issue.record("GetMass answered without the physics world")
            return
        }
        var masses: [ReferenceKey: Float] = [:]
        fixture.session.bridge.havokMass = { masses[$0] }
        #expect(fixture.call("GetMass", returnType: .float) == .returned(.float(0)))
        masses[fixture.key] = 12.5
        #expect(fixture.call("GetMass", returnType: .float) == .returned(.float(12.5)))
    }
}
