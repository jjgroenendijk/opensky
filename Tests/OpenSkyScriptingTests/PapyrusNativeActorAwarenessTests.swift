// `HasLOS`, `IsDetectedBy`, `GetCurrentPackage`, and `Utility.WaitMenuMode` over
// synthetic perception and package answers.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyPerceptionInterface
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
import Testing

@MainActor
struct PapyrusNativeActorAwarenessTests {
    private static let otherID: UInt32 = PapyrusNativeReferenceFixture.doorID

    private func call(
        _ fixture: PapyrusNativeReferenceFixture,
        _ name: String,
        arguments: [PapyrusValue] = []
    ) -> PapyrusNativeResult {
        fixture.registry.invoke(PapyrusWorldFixture.methodCall(
            "Actor", name, receiver: fixture.receiver, arguments: arguments
        ))
    }

    private func pairs(
        _ fixture: PapyrusNativeReferenceFixture,
        _ entries: [(observer: ReferenceKey, target: ReferenceKey, sees: Bool, detected: Bool)]
    ) {
        var map: [DetectionPairKey: DetectionPairState] = [:]
        for entry in entries {
            var state = DetectionPairState()
            state.hasLineOfSight = entry.sees
            state.state = entry.detected ? .detected : .suspicious
            map[DetectionPairKey(observer: entry.observer, target: entry.target)] = state
        }
        fixture.session.bridge.detection = { DetectionResolution(pairs: map) }
    }

    @Test func hasLOSAsksThisActorAboutTheOther() throws {
        let fixture = try PapyrusNativeReferenceFixture.make()
        let other = PapyrusNativeReferenceFixture.key(Self.otherID)
        pairs(fixture, [
            (fixture.key, other, true, false),
            (other, fixture.key, false, true)
        ])
        let argument = PapyrusValue.object(fixture.handle(Self.otherID))
        #expect(call(fixture, "HasLOS", arguments: [argument]) == .returned(.boolean(true)))
        #expect(call(fixture, "IsDetectedBy", arguments: [argument]) == .returned(.boolean(true)))
    }

    @Test func anUntrackedPairOrNoPerceptionFails() throws {
        let fixture = try PapyrusNativeReferenceFixture.make()
        let argument = PapyrusValue.object(fixture.handle(Self.otherID))
        #expect(PapyrusWorldFixture.isInvalidArguments(call(
            fixture,
            "HasLOS",
            arguments: [argument]
        )))
        pairs(fixture, [])
        #expect(PapyrusWorldFixture.isInvalidArguments(
            call(fixture, "IsDetectedBy", arguments: [argument])
        ))
    }

    @Test func getCurrentPackageNamesThePackageOrNone() throws {
        let fixture = try PapyrusNativeReferenceFixture.make()
        let package = FormID(0x0000_0123)
        fixture.session.bridge.currentPackage = { $0 == fixture.key ? package : nil }
        let expected = fixture.session.world.objectHandle(
            for: .plugin(name: PapyrusWorldFixture.pluginName, objectID: 0x123)
        )
        #expect(call(fixture, "GetCurrentPackage") == .returned(.object(expected)))
        fixture.session.bridge.currentPackage = { _ in nil }
        #expect(call(fixture, "GetCurrentPackage") == .returned(.none))
    }

    @Test func waitMenuModeSuspendsLikeWait() throws {
        let fixture = try PapyrusNativeReferenceFixture.make()
        let result = fixture.registry.invoke(PapyrusNativeCall(
            kind: .staticFunction, scriptName: "Utility", functionName: "WaitMenuMode",
            receiver: nil, arguments: [.float(2)], returnType: .none
        ))
        #expect(result == .suspended(.realSeconds(2)))
    }
}
