// The script-state natives over a synthetic lever: flags, values, form links,
// ownership, player controls, added forms, keyword data, and the reference writes.

import Foundation
@testable import OpenSkyCrimeInterface
@testable import OpenSkyFormatsESM
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
@testable import OpenSkyScriptingInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct PapyrusNativeScriptStateTests {
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

    private func state(_ fixture: Fixture) -> ScriptedReferenceState? {
        fixture.session.worldState.component(ScriptedReferenceState.self, for: fixture.key)
    }

    @Test func aFlagIsSetReadAndClearedToNoState() throws {
        let fixture = try Fixture.make()
        #expect(call(fixture, "Actor", "IsGhost", returnType: .boolean) ==
            .returned(.boolean(false)))
        #expect(call(fixture, "Actor", "SetGhost") == .returned(.none))
        #expect(call(fixture, "Actor", "IsGhost", returnType: .boolean) ==
            .returned(.boolean(true)))
        #expect(call(fixture, "Actor", "SetGhost", [.boolean(false)]) == .returned(.none))
        #expect(call(fixture, "Actor", "IsGhost", returnType: .boolean) ==
            .returned(.boolean(false)))
        #expect(state(fixture) == nil)
    }

    @Test func valuesAndFormLinksReadBack() throws {
        let fixture = try Fixture.make()
        let door = fixture.handle(Fixture.doorID)
        #expect(call(fixture, "Actor", "SetVoiceRecoveryTime", [.float(2.5)]) == .returned(.none))
        #expect(call(fixture, "Actor", "GetVoiceRecoveryTime", returnType: .float)
            == .returned(.float(2.5)))
        #expect(call(fixture, "Actor", "SetCrimeFaction", [.object(door)]) == .returned(.none))
        #expect(call(fixture, "Actor", "GetCrimeFaction", returnType: .object("Faction"))
            == .returned(.object(door)))
        #expect(call(fixture, "Location", "SetKeywordData", [.object(door), .float(3)])
            == .returned(.none))
        #expect(call(fixture, "Location", "GetKeywordData", [.object(door)], returnType: .float)
            == .returned(.float(3)))
    }

    /// One owner at a time; a None owner is a cleared owner, not "no script set one".
    @Test func ownershipHasOneOwnerAndCanBeCleared() throws {
        let fixture = try Fixture.make()
        let door = fixture.handle(Fixture.doorID)
        let doorKey = Fixture.key(Fixture.doorID)
        #expect(fixture.session.bridge.scriptedOwner(of: fixture.key) == nil)

        _ = call(fixture, "ObjectReference", "SetActorOwner", [.object(door)])
        #expect(call(fixture, "ObjectReference", "GetActorOwner", returnType: .object("ActorBase"))
            == .returned(.object(door)))
        _ = call(fixture, "ObjectReference", "SetFactionOwner", [.object(door)])
        #expect(fixture.session.bridge.scriptedOwner(of: fixture.key)
            == .some(.faction(doorKey, requiredRank: 0)))
        #expect(call(fixture, "ObjectReference", "GetActorOwner", returnType: .object("ActorBase"))
            == .returned(.none))

        _ = call(fixture, "ObjectReference", "SetActorOwner", [.none])
        #expect(fixture.session.bridge.scriptedOwner(of: fixture.key) == .some(nil))
    }

    @Test func playerControlsUseEachNativesDefaults() throws {
        let fixture = try Fixture.make()
        func isEnabled(_ control: String) -> PapyrusNativeResult {
            call(fixture, "Game", "Is\(control)ControlsEnabled", returnType: .boolean)
        }
        #expect(call(fixture, "Game", "DisablePlayerControls") == .returned(.none))
        #expect(isEnabled("Movement") == .returned(.boolean(false)))
        #expect(isEnabled("Looking") == .returned(.boolean(true)))
        #expect(call(fixture, "Game", "EnablePlayerControls") == .returned(.none))
        #expect(isEnabled("Movement") == .returned(.boolean(true)))
        #expect(fixture.session.worldState.component(ScriptedReferenceState.self, for: .player)
            == nil)
    }

    @Test func addedFormsJoinTheListOnce() throws {
        let fixture = try Fixture.make()
        let door = fixture.handle(Fixture.doorID)
        _ = call(fixture, "FormList", "AddForm", [.object(door)])
        _ = call(fixture, "FormList", "AddForm", [.object(door)])
        #expect(call(fixture, "FormList", "GetSize", returnType: .integer)
            == .returned(.integer(1)))
        #expect(call(fixture, "FormList", "HasForm", [.object(door)], returnType: .boolean)
            == .returned(.boolean(true)))
        _ = call(fixture, "FormList", "RemoveAddedForm", [.object(door)])
        #expect(state(fixture) == nil)
    }

    @Test func openStateScaleAngleAndTheEditorPlacement() throws {
        let fixture = try Fixture.make()
        #expect(fixture.call("GetOpenState", returnType: .integer) == .returned(.integer(3)))
        #expect(fixture.call("SetOpen") == .returned(.none))
        #expect(fixture.call("GetOpenState", returnType: .integer) == .returned(.integer(1)))

        #expect(fixture.call("SetScale", arguments: [.float(2)]) == .returned(.none))
        #expect(fixture.call("GetScale", returnType: .float) == .returned(.float(2)))
        #expect(fixture.call("SetAngle", arguments: [.float(0), .float(0), .float(90)])
            == .returned(.none))
        guard case let .returned(.float(angle)) = fixture.call("GetAngleZ", returnType: .float)
        else {
            Issue.record("GetAngleZ should answer a float")
            return
        }
        #expect(abs(angle - 90) < 0.001)
        #expect(PapyrusWorldFixture.isInvalidArguments(
            fixture.call("SetScale", arguments: [.float(-1)])
        ))

        #expect(fixture.call("MoveToMyEditorLocation") == .returned(.none))
        #expect(fixture.call("GetScale", returnType: .float) == .returned(.float(1)))
    }

    /// A blocked reference still records the activation, but it does not open.
    @Test func blockedActivationDoesNotOpen() throws {
        let fixture = try Fixture.make()
        #expect(fixture.call("BlockActivation") == .returned(.none))
        #expect(fixture.call("IsActivationBlocked", returnType: .boolean)
            == .returned(.boolean(true)))
        fixture.session.bridge.activate(fixture.key, by: .player, togglesOpen: true)
        let activation = fixture.session.bridge.referenceState(for: fixture.key)?.activation
        #expect(activation?.activationCount == 1)
        #expect(activation?.isOpen == false)
    }

    @Test func aiAndTheStatesOpenSkyDoesNotSimulate() throws {
        let fixture = try Fixture.make()
        #expect(call(fixture, "Actor", "EnableAI", [.boolean(false)]) == .returned(.none))
        #expect(call(fixture, "Actor", "IsAIEnabled", returnType: .boolean)
            == .returned(.boolean(false)))
        #expect(call(fixture, "Actor", "IsBleedingOut", returnType: .boolean)
            == .returned(.boolean(false)))
        #expect(PapyrusWorldFixture.isInvalidArguments(
            call(fixture, "Actor", "GetCombatState", returnType: .integer)
        ))
    }
}
