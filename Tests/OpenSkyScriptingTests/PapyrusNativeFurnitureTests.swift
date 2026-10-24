// The furniture natives answer from the app's seats through `PapyrusFurnitureBridge`.

import Foundation
import OpenSkyFormatsESM
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
import Testing

private struct InUseQuestion {
    let furniture: ReferenceKey
    let marker: Int?
    let ignoringReserved: Bool
}

@MainActor
private final class FakeFurniture: PapyrusFurnitureBridge {
    var asked: [InUseQuestion] = []
    var rotation: Float?

    func isFurnitureInUse(_ furniture: ReferenceKey, marker: Int?, ignoringReserved: Bool) -> Bool {
        asked.append(InUseQuestion(
            furniture: furniture,
            marker: marker,
            ignoringReserved: ignoringReserved
        ))
        return marker != 1
    }

    func setSittingRotation(degrees: Float) {
        rotation = degrees
    }
}

@MainActor
struct PapyrusNativeFurnitureTests {
    private typealias Fixture = PapyrusNativeReferenceFixture

    @Test func inUseAsksTheBridgeWithTheMarkerAndTheReservationFlag() throws {
        let fixture = try Fixture.make()
        let furniture = FakeFurniture()
        fixture.session.bridge.furniture = furniture
        #expect(fixture.call("IsFurnitureInUse", returnType: .boolean) == .returned(.boolean(true)))
        #expect(fixture.call(
            "IsFurnitureMarkerInUse", arguments: [.integer(1), .boolean(true)], returnType: .boolean
        ) == .returned(.boolean(false)))
        #expect(furniture.asked.map(\.marker) == [nil, 1])
        #expect(furniture.asked.map(\.ignoringReserved) == [false, true])
        #expect(furniture.asked.allSatisfy { $0.furniture == fixture.key })
    }

    @Test func withoutTheBridgeTheCallFails() throws {
        let fixture = try Fixture.make()
        guard case .failed = fixture.call("IsFurnitureInUse", returnType: .boolean) else {
            Issue.record("IsFurnitureInUse answered without seats")
            return
        }
    }

    @Test func sittingRotationReachesTheBridge() throws {
        let fixture = try Fixture.make()
        let furniture = FakeFurniture()
        fixture.session.bridge.furniture = furniture
        let result = fixture.registry.invoke(PapyrusNativeCall(
            kind: .staticFunction, scriptName: "Game", functionName: "SetSittingRotation",
            receiver: nil, arguments: [.float(-90)], returnType: .none
        ))
        #expect(result == .returned(.none))
        #expect(furniture.rotation == -90)
    }
}
