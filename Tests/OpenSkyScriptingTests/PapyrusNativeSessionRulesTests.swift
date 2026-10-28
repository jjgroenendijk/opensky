// The game-rule and session natives over a synthetic lever: deferred kills, feeding,
// stolen values, flying, the app hooks, model nodes, the sun gaze, and traced stubs.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
@testable import OpenSkyScriptingInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct PapyrusNativeSessionRulesTests {
    private typealias Fixture = PapyrusNativeReferenceFixture

    private func call(
        _ fixture: Fixture, _ script: String, _ name: String,
        _ arguments: [PapyrusValue] = [], returnType: PapyrusType = .none
    ) -> PapyrusNativeResult {
        fixture.registry.invoke(PapyrusWorldFixture.methodCall(
            script, name, receiver: fixture.receiver, arguments: arguments,
            returnType: returnType
        ))
    }

    private func flags(_ fixture: Fixture, of key: ReferenceKey) -> ScriptedReferenceState {
        fixture.session.bridge.scriptedState(of: key)
    }

    @Test func aDeferredKillIsSetAndEnded() throws {
        let fixture = try Fixture.make()
        _ = call(fixture, "Actor", "StartDeferredKill")
        #expect(flags(fixture, of: fixture.key).flag(ScriptedStateName.deferredKill) == true)
        _ = call(fixture, "Actor", "EndDeferredKill")
        #expect(flags(fixture, of: fixture.key).flag(ScriptedStateName.deferredKill) == nil)
        #expect(call(fixture, "Actor", "IsInKillMove", returnType: .boolean) ==
            .returned(.boolean(false)))
    }

    @Test func cannibalismMarksTheTargetEaten() throws {
        let fixture = try Fixture.make()
        _ = call(fixture, "Actor", "StartCannibal", [.object(fixture.handle(Fixture.doorID))])
        #expect(flags(fixture, of: Fixture.key(Fixture.doorID))
            .flag(ScriptedStateName.eaten) == true)
    }

    @Test func stolenValuesSplitByWitness() throws {
        let fixture = try Fixture.make()
        fixture.session.bridge.noteStolenValue(30, from: fixture.key, witnessed: true)
        fixture.session.bridge.noteStolenValue(12, from: fixture.key, witnessed: false)
        fixture.session.bridge.noteStolenValue(8, from: fixture.key, witnessed: false)
        #expect(call(fixture, "Faction", "GetStolenItemValueCrime", returnType: .integer) ==
            .returned(.integer(30)))
        #expect(call(fixture, "Faction", "GetStolenItemValueNoCrime", returnType: .integer) ==
            .returned(.integer(20)))
    }

    @Test func theExtendedFlyingSetterSharesTheFlag() throws {
        let fixture = try Fixture.make()
        _ = call(fixture, "Actor", "SetAllowFlyingEx", [.boolean(true)])
        #expect(call(fixture, "Actor", "IsAllowedToFly", returnType: .boolean) ==
            .returned(.boolean(true)))
    }

    @Test func flyingMountLandingRequestsAreKeptOnThePlayer() throws {
        let fixture = try Fixture.make()
        let name = ScriptedStateName.flyingMountLandingRefused
        _ = call(fixture, "Game", "SetAllowFlyingMountLandingRequests", [.boolean(false)])
        #expect(flags(fixture, of: .player).flag(name) == true)
        _ = call(fixture, "Game", "SetAllowFlyingMountLandingRequests", [.boolean(true)])
        #expect(flags(fixture, of: .player).flag(name) == nil)
    }

    @Test func aGameHookRunsAndAMissingHookFails() throws {
        let fixture = try Fixture.make()
        #expect(PapyrusWorldFixture.isInvalidArguments(call(fixture, "Debug", "SetGodMode")))
        var godMode: Bool?
        fixture.session.bridge.gameNatives.setGodMode = { godMode = $0 }
        #expect(call(fixture, "Debug", "SetGodMode", [.boolean(false)]) == .returned(.none))
        #expect(godMode == false)
    }

    @Test func footIkSwitchesThroughItsHook() throws {
        let fixture = try Fixture.make()
        var footIk: Bool?
        fixture.session.bridge.gameNatives.setFootIK = { footIk = $0 }
        #expect(call(fixture, "Debug", "SetFootIK", [.boolean(false)]) == .returned(.none))
        #expect(footIk == false)
    }

    @Test func aFadeCarriesItsColourAndTimes() throws {
        let fixture = try Fixture.make()
        var fade: PapyrusFade?
        fixture.session.bridge.gameNatives.fade = { fade = $0 }
        _ = call(fixture, "Game", "FadeOutGame", [
            .boolean(false), .boolean(false), .float(2), .float(1)
        ])
        #expect(fade == PapyrusFade(
            fadingOut: false, black: false, secondsBeforeFade: 2, duration: 1
        ))
    }

    @Test func theGrabbedReferenceComesFromTheHook() throws {
        let fixture = try Fixture.make()
        #expect(call(fixture, "Game", "GetPlayerGrabbedRef", returnType: .object("ObjectReference"))
            == .returned(.none))
        fixture.session.bridge.gameNatives.playerGrabbedReference = { fixture.key }
        #expect(call(fixture, "Game", "GetPlayerGrabbedRef", returnType: .object("ObjectReference"))
            == .returned(.object(fixture.receiver)))
    }

    /// A model still loading suspends the call on the token the app answers.
    @Test func nodeLookupsAnswerFoundMissingOrLater() throws {
        let fixture = try Fixture.make()
        var answer = PapyrusNodeAnswer.found(
            MatrixMath.placement(position: [7, 8, 9], rotation: [0, 0, 0.5], scale: 1)
        )
        fixture.session.bridge.gameNatives.nodeTransform = { _, _, _ in answer }
        #expect(call(fixture, "ObjectReference", "HasNode", [.string("Seat")], returnType: .boolean)
            == .returned(.boolean(true)))
        let target = PapyrusValue.object(fixture.handle(Fixture.doorID))
        #expect(call(fixture, "ObjectReference", "MoveToNode", [target, .string("Seat")])
            == .returned(.none))
        let moved = try #require(fixture.session.bridge.referenceState(for: fixture.key))
        #expect(moved.transform.position == [7, 8, 9])
        #expect(abs(moved.transform.rotation.z - 0.5) < 1e-4)
        answer = .missing
        #expect(call(fixture, "ObjectReference", "HasNode", [.string("Seat")], returnType: .boolean)
            == .returned(.boolean(false)))
        answer = .loading(token: 42)
        #expect(call(fixture, "ObjectReference", "HasNode", [.string("Seat")], returnType: .boolean)
            == .suspended(.external(42)))
    }

    @Test func aMissingSubsystemIsATracedStub() throws {
        let fixture = try Fixture.make()
        #expect(call(fixture, "Actor", "SetEyeTexture", [.none]) == .deviated(.none, .stubbed))
    }

    @Test func gazingNeedsTheLookWithinTheCone() {
        #expect(PapyrusSunGaze.isGazing(forward: [1, 0, 0], towardSun: [1, 0.05, 0]))
        #expect(!PapyrusSunGaze.isGazing(forward: [1, 0, 0], towardSun: [1, 0.2, 0]))
        #expect(!PapyrusSunGaze.isGazing(forward: .zero, towardSun: [1, 0, 0]))
    }

    @Test func theSunIsZeroWhileItIsDown() throws {
        let fixture = try Fixture.make()
        #expect(call(fixture, "Game", "GetSunPositionZ", returnType: .float) ==
            .returned(.float(0)))
        fixture.session.bridge.sessionNatives.towardSun = { [0, 0, 1] }
        fixture.session.bridge.sessionNatives.playerView = {
            PapyrusPlayerView(eye: [0, 0, 100], forward: [1, 0, 0])
        }
        #expect(call(fixture, "Game", "GetSunPositionZ", returnType: .float) ==
            .returned(.float(100 + PapyrusNativeFunctions.sunDistance)))
    }
}
