// The trap census natives: trigger occupancy, linked chains, the base object, and
// the traced stubs that answer an empty value instead of stopping a script.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyPhysics
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
@testable import OpenSkyScriptingInterface
import Testing

@MainActor
private final class FakeObjectAnimation: PapyrusObjectAnimationBridge {
    var hasGraph = true
    var played: [String] = []
    var awaited: [String] = []

    func playAnimation(_ event: String, on _: ReferenceKey) -> Bool {
        played.append(event)
        return hasGraph
    }

    func awaitAnimationEvent(_ event: String, on _: ReferenceKey) -> UInt64? {
        awaited.append(event)
        return hasGraph ? 77 : nil
    }

    var variables: [String: PapyrusValue] = [:]

    func animationVariable(_ name: String, on _: ReferenceKey) -> PapyrusValue? {
        variables[name]
    }

    func setAnimationVariable(_ name: String, to value: PapyrusValue, on _: ReferenceKey) -> Bool {
        guard variables[name] != nil else { return false }
        variables[name] = value
        return true
    }

    var openState: Int32?

    func openStateCode(of _: ReferenceKey) -> Int32? {
        openState
    }
}

@MainActor
struct PapyrusNativeTrapTests {
    private typealias Fixture = PapyrusNativeReferenceFixture

    @Test func triggerObjectCountFollowsEnterAndLeave() throws {
        let fixture = try Fixture.make()
        let count = { fixture.call("GetTriggerObjectCount", returnType: .integer) }
        #expect(count() == .returned(.integer(0)))
        fixture.session.bridge.handleTriggerTransition(
            TriggerTransitionEvent(reference: fixture.key, phase: .enter)
        )
        #expect(count() == .returned(.integer(1)))
        fixture.session.bridge.handleTriggerTransition(
            TriggerTransitionEvent(reference: fixture.key, phase: .leave)
        )
        #expect(count() == .returned(.integer(0)))
    }

    @Test func nthLinkedRefFollowsTheUntaggedChain() throws {
        let fixture = try Fixture.make(links: [(keyword: nil, ref: Fixture.leverID)])
        let first = fixture.call(
            "GetNthLinkedRef", arguments: [.integer(1)], returnType: .object("ObjectReference")
        )
        #expect(first == .returned(.object(fixture.receiver)))
        let third = fixture.call(
            "GetNthLinkedRef", arguments: [.integer(3)], returnType: .object("ObjectReference")
        )
        #expect(third == .returned(.object(fixture.receiver)))
        let none = fixture.call(
            "GetNthLinkedRef", arguments: [.integer(0)], returnType: .object("ObjectReference")
        )
        #expect(none == .returned(.none))
    }

    @Test func baseObjectIsAHandle() throws {
        let fixture = try Fixture.make()
        let base = fixture.call("GetBaseObject", returnType: .object("Form"))
        guard case let .returned(.object(handle)) = base else {
            Issue.record("GetBaseObject did not return an object: \(base)")
            return
        }
        #expect(fixture.session.world.referenceKey(for: handle)
            == .plugin(name: PapyrusWorldFixture.pluginName, objectID: 0x100))
    }

    @Test func stubsAnswerAnEmptyValueAndCountAsStubbed() throws {
        let fixture = try Fixture.make()
        #expect(fixture.call("SetMotionType") == .deviated(.none, .stubbed))
        #expect(fixture.call("ApplyHavokImpulse") == .deviated(.none, .stubbed))
        #expect(fixture.call("IsLockBroken", returnType: .boolean) == .returned(.boolean(false)))
        #expect(fixture.call("GetAngleX", returnType: .float) == .returned(.float(0)))
    }

    @Test func getFormHandsBackTheFormBehindALoadOrderID() throws {
        let fixture = try Fixture.make()
        let getForm = { (formID: Int32) in
            fixture.registry.invoke(PapyrusNativeCall(
                kind: .staticFunction, scriptName: "Game", functionName: "GetForm",
                receiver: nil, arguments: [.integer(formID)], returnType: .object("Form")
            ))
        }
        #expect(getForm(Int32(Fixture.leverID)) == .returned(.object(fixture.receiver)))
        #expect(getForm(0) == .returned(.none))
    }

    @Test func animationEventWaitIsPacedAndAnswersTrue() throws {
        let fixture = try Fixture.make()
        let result = fixture.call(
            "WaitForAnimationEvent", arguments: [.string("EndLoop")], returnType: .boolean
        )
        #expect(result == .suspended(.realSecondsAnswering(
            PapyrusNativeFunctions.animationEventWaitSeconds, .boolean(true)
        )))
    }

    @Test func animationNativesDriveAnObjectGraph() throws {
        let fixture = try Fixture.make()
        let graphs = FakeObjectAnimation()
        fixture.session.bridge.objectAnimation = graphs
        let play = fixture.call(
            "PlayAnimation", arguments: [.string("Trigger")], returnType: .boolean
        )
        #expect(play == .returned(.boolean(true)))
        let wait = fixture.call(
            "PlayAnimationAndWait", arguments: [.string("Reset"), .string("Done")],
            returnType: .boolean
        )
        #expect(wait == .suspended(.external(77)))
        #expect(graphs.played == ["Trigger", "Reset"])
        #expect(graphs.awaited == ["Done"])
        graphs.hasGraph = false
        let paced = fixture.call(
            "WaitForAnimationEvent", arguments: [.string("Done")], returnType: .boolean
        )
        #expect(paced == .suspended(.realSecondsAnswering(
            PapyrusNativeFunctions.animationEventWaitSeconds, .boolean(true)
        )))
    }

    @Test func animationVariablesReadAndWriteTheGraphInTheNamedType() throws {
        let fixture = try Fixture.make()
        let graphs = FakeObjectAnimation()
        graphs.variables = ["bOpen": .boolean(false), "iState": .integer(2)]
        fixture.session.bridge.objectAnimation = graphs
        #expect(fixture.call(
            "SetAnimationVariableBool",
            arguments: [.string("bOpen"), .boolean(true)]
        )
            == .returned(.none))
        #expect(graphs.variables["bOpen"] == .boolean(true))
        #expect(fixture.call(
            "GetAnimationVariableInt",
            arguments: [.string("bOpen")],
            returnType: .integer
        )
            == .returned(.integer(1)))
        #expect(fixture.call("SetAnimationVariableInt", arguments: [.string("iState"), .integer(5)])
            == .returned(.none))
        #expect(fixture.call(
            "GetAnimationVariableFloat",
            arguments: [.string("iState")],
            returnType: .float
        )
            == .returned(.float(5)))
        #expect(PapyrusWorldFixture.isInvalidArguments(fixture.call(
            "SetAnimationVariableFloat", arguments: [.string("fMissing"), .float(1)]
        )))

        let send = fixture.registry.invoke(PapyrusWorldFixture.methodCall(
            "Debug", "SendAnimationEvent", receiver: nil,
            arguments: [.object(fixture.receiver), .string("Open")]
        ))
        #expect(send == .returned(.none))
        #expect(graphs.played == ["Open"])
    }

    @Test func processTrapHitNeedsAnActor() throws {
        let fixture = try Fixture.make()
        let result = fixture.call(
            "ProcessTrapHit", arguments: [.object(fixture.receiver), .float(10)]
        )
        guard case .failed = result else {
            Issue.record("ProcessTrapHit on a lever should fail: \(result)")
            return
        }
    }

    @Test func placeAtMeHandsBackTheReferenceTheBridgePlaced() throws {
        let fixture = try Fixture.make()
        let placement = FakeTrapWorld()
        let place = { (form: PapyrusObjectHandle) in
            fixture.call(
                "PlaceAtMe", arguments: [.object(form), .integer(2)],
                returnType: .object("ObjectReference")
            )
        }
        guard
            case let .returned(.object(form)) = fixture.call(
                "GetBaseObject", returnType: .object("Form")
            )
        else {
            Issue.record("GetBaseObject did not return a form")
            return
        }
        #expect(place(form) == .deviated(.none, .stubbed))
        fixture.session.bridge.trapWorld = placement
        guard case let .returned(.object(placed)) = place(form) else {
            Issue.record("PlaceAtMe did not return a reference")
            return
        }
        #expect(fixture.session.world.referenceKey(for: placed) == .generated(42))
        #expect(placement.placed.first?.anchor == fixture.key)
        #expect(placement.placed.first?.count == 2)
        #expect(placement.placed.first?.base
            == .plugin(name: PapyrusWorldFixture.pluginName, objectID: 0x100))
    }

    @Test func applyHavokImpulseScalesTheUnitDirectionByTheMagnitude() throws {
        let fixture = try Fixture.make()
        let trapWorld = FakeTrapWorld()
        fixture.session.bridge.trapWorld = trapWorld
        let result = fixture.call(
            "ApplyHavokImpulse", arguments: [.float(0), .float(0), .float(-4), .float(50)]
        )
        #expect(result == .returned(.none))
        #expect(trapWorld.impulses.first?.impulse == SIMD3(0, 0, -50))
        #expect(trapWorld.impulses.first?.reference == fixture.key)
        let zero = fixture.call(
            "ApplyHavokImpulse", arguments: [.float(0), .float(0), .float(0), .float(50)]
        )
        #expect(PapyrusWorldFixture.isInvalidArguments(zero))
        #expect(trapWorld.impulses.count == 1)
    }

    @Test func pushActorAwayPushesFromTheReceiver() throws {
        let fixture = try Fixture.make()
        let trapWorld = FakeTrapWorld()
        fixture.session.bridge.trapWorld = trapWorld
        let result = fixture.call(
            "PushActorAway", arguments: [.object(fixture.receiver), .float(2)]
        )
        #expect(result == .returned(.none))
        #expect(trapWorld.pushes.first?.source == fixture.key)
        #expect(trapWorld.pushes.first?.direction == nil)
        #expect(trapWorld.pushes.first?.speed == 2 * PapyrusNativeFunctions.knockbackSpeedPerForce)
        _ = fixture.call("PushActorAway", arguments: [.object(fixture.receiver), .float(-1)])
        #expect(trapWorld.pushes.last?.speed == -PapyrusNativeFunctions.knockbackSpeedPerForce)
    }
}
