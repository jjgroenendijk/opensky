// `HasLOS`, `IsDetectedBy`, `GetCurrentPackage`, `GetLightLevel`, and
// `Utility.WaitMenuMode` over synthetic perception, light, and package answers.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyPerceptionInterface
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
import OpenSkyWorldState
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

    private struct Sight {
        let observer: ReferenceKey
        let target: ReferenceKey
        let sees: Bool
        let detected: Bool

        init(_ observer: ReferenceKey, _ target: ReferenceKey, _ sees: Bool, _ detected: Bool) {
            self.observer = observer
            self.target = target
            self.sees = sees
            self.detected = detected
        }
    }

    private func pairs(
        _ fixture: PapyrusNativeReferenceFixture,
        _ entries: [Sight]
    ) {
        var map: [DetectionPairKey: DetectionPairState] = [:]
        for entry in entries {
            var state = DetectionPairState()
            state.hasLineOfSight = entry.sees
            state.state = entry.detected ? .detected : .suspicious
            map[DetectionPairKey(observer: entry.observer, target: entry.target)] = state
        }
        fixture.session.bridge.perceptionNatives.detection = { DetectionResolution(pairs: map) }
    }

    @Test func hasLOSAsksThisActorAboutTheOther() throws {
        let fixture = try PapyrusNativeReferenceFixture.make()
        let other = PapyrusNativeReferenceFixture.key(Self.otherID)
        pairs(fixture, [
            Sight(fixture.key, other, true, false),
            Sight(other, fixture.key, false, true)
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
        fixture.session.bridge.sessionNatives.currentPackage = { $0 == fixture.key ? package : nil }
        let expected = fixture.session.world.objectHandle(
            for: .plugin(name: PapyrusWorldFixture.pluginName, objectID: 0x123)
        )
        #expect(call(fixture, "GetCurrentPackage") == .returned(.object(expected)))
        fixture.session.bridge.sessionNatives.currentPackage = { _ in nil }
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

    @Test func lightLevelScalesTheDetectionLevel() throws {
        let fixture = try PapyrusNativeReferenceFixture.make()
        guard case .failed = call(fixture, "GetLightLevel") else {
            Issue.record("GetLightLevel answered without the renderer")
            return
        }
        var sampled: SIMD3<Float>?
        fixture.session.bridge.perceptionNatives.lightLevel = { feet in
            sampled = feet
            return 0.25
        }
        #expect(call(fixture, "GetLightLevel") == .returned(.float(25)))
        #expect(sampled == fixture.session.bridge.referenceState(for: fixture.key)?.transform
            .position)
    }
}
