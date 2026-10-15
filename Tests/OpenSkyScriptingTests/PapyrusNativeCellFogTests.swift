// The `Cell` fog natives hand their change to the renderer hook, with colours in 0...1.

import Foundation
import OpenSkyFormatsESM
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
import Testing

@MainActor
struct PapyrusNativeCellFogTests {
    @Test func fogNativesReachTheRenderer() throws {
        let fixture = try PapyrusNativeReferenceFixture.make()
        let cell = { (name: String, arguments: [PapyrusValue]) in
            fixture.registry.invoke(PapyrusWorldFixture.methodCall(
                "Cell", name, receiver: fixture.handle(0x100), arguments: arguments
            ))
        }
        guard case .failed = cell("SetFogPower", [.float(2)]) else {
            Issue.record("SetFogPower answered without the renderer")
            return
        }
        var changes: [PapyrusFogChange] = []
        var cells: Set<FormID> = []
        fixture.session.bridge.cellFog = { formID, change in
            cells.insert(formID)
            changes.append(change)
            return true
        }
        let colour = [255, 0, 0, 0, 0, 510].map { PapyrusValue.integer(Int32($0)) }
        #expect(cell("SetFogColor", colour) == .returned(.none))
        #expect(cell("SetFogPlanes", [.float(0), .float(1000)]) == .returned(.none))
        #expect(cell("SetFogPower", [.float(2)]) == .returned(.none))
        #expect(changes == [
            .colours(near: SIMD3(1, 0, 0), far: SIMD3(0, 0, 1)),
            .planes(near: 0, far: 1000),
            .power(2)
        ])
        #expect(cells.count == 1)
        #expect(cell("SetFogPlanes", [.float(.nan), .float(1)]) != .returned(.none))
    }
}
