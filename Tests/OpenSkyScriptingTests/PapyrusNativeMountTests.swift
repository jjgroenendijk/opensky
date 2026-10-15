// `GetPlayersLastRiddenHorse` reads the horse the vehicle runtime last saw the player ride.

import Foundation
import OpenSkyFormatsESM
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
import Testing

@MainActor
struct PapyrusNativeMountTests {
    @Test func lastRiddenHorseReadsTheVehicleRuntime() throws {
        let fixture = try PapyrusNativeReferenceFixture.make()
        let read = {
            fixture.registry.invoke(PapyrusNativeCall(
                kind: .staticFunction, scriptName: "Game",
                functionName: "GetPlayersLastRiddenHorse", receiver: nil, arguments: [],
                returnType: .object("Actor")
            ))
        }
        guard case .failed = read() else {
            Issue.record("GetPlayersLastRiddenHorse answered without the vehicle runtime")
            return
        }
        var horse: ReferenceKey?
        fixture.session.bridge.playersLastMount = { horse }
        #expect(read() == .returned(.none))
        horse = fixture.key
        #expect(read() == .returned(.object(fixture.receiver)))
    }
}
