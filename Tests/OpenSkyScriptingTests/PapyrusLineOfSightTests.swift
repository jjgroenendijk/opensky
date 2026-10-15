// Line-of-sight registrations: the first check reports the state a full registration
// starts in, single registrations end after their event, and only the registering
// instance hears it.

import Foundation
import OpenSkyFormatsESM
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
import Testing

@MainActor
struct PapyrusLineOfSightTests {
    private typealias Fixture = PapyrusNativeReferenceFixture
    private static let instance = PapyrusInstanceKey(reference: .player, scriptName: "Quest")
    private static let pair = LineOfSightWatch.Pair(
        viewer: .player, target: Fixture.key(Fixture.doorID)
    )

    private static func step(_ watch: inout LineOfSightWatch, sees: Bool?) -> [Bool] {
        watch.step(isLive: { _ in true }, sees: { _ in sees }).map(\.gained)
    }

    @Test func aFullRegistrationReportsItsStartAndEveryChange() {
        var watch = LineOfSightWatch()
        watch.register(Self.instance, Self.pair, mode: .both)
        #expect(Self.step(&watch, sees: false) == [false])
        #expect(Self.step(&watch, sees: false).isEmpty)
        #expect(Self.step(&watch, sees: nil).isEmpty)
        #expect(Self.step(&watch, sees: true) == [true])
        #expect(Self.step(&watch, sees: false) == [false])
    }

    @Test func singleRegistrationsEndAfterTheirEvent() {
        var watch = LineOfSightWatch()
        watch.register(Self.instance, Self.pair, mode: .singleGain)
        #expect(Self.step(&watch, sees: false).isEmpty)
        #expect(Self.step(&watch, sees: true) == [true])
        #expect(watch.isEmpty)
        watch.register(Self.instance, Self.pair, mode: .singleLost)
        #expect(Self.step(&watch, sees: true).isEmpty)
        #expect(Self.step(&watch, sees: false) == [false])
        #expect(watch.isEmpty)
    }

    @Test func aRetiredInstanceLosesItsRegistrations() {
        var watch = LineOfSightWatch()
        watch.register(Self.instance, Self.pair, mode: .both)
        #expect(watch.step(isLive: { _ in false }, sees: { _ in true }).isEmpty)
        #expect(watch.isEmpty)
    }

    @Test func theViewHoldsOnlyPointsInsideTheFieldOfView() {
        let view = LineOfSightWatch.View(
            forward: SIMD3(0, 1, 0), right: SIMD3(1, 0, 0), up: SIMD3(0, 0, 1),
            tanHalfWidth: 1, tanHalfHeight: 0.5
        )
        #expect(view.contains(SIMD3(0.9, 1, 0.4)))
        #expect(!view.contains(SIMD3(1.1, 1, 0)))
        #expect(!view.contains(SIMD3(0, 1, 0.6)))
        #expect(!view.contains(SIMD3(0, -1, 0)))
    }

    @Test func theNativesRegisterAndTheBridgeQueuesTheEvents() throws {
        let fixture = try Fixture.make(events: [
            ("OnGainLOS", PapyrusWorldFixture.probeBody(note: "gain")),
            ("OnLostLOS", PapyrusWorldFixture.probeBody(note: "lost"))
        ])
        let world = fixture.session.world
        let handle = try #require(world.instancesByKey[
            PapyrusInstanceKey(reference: fixture.key, scriptName: "Lever")
        ])
        let register = { (name: String) in
            fixture.registry.invoke(PapyrusWorldFixture.methodCall(
                "Form", name, receiver: handle,
                arguments: [.object(fixture.handle(Fixture.doorID)), .object(fixture.receiver)]
            ))
        }
        #expect(register("RegisterForSingleLOSGain") == .returned(.none))
        var sees = false
        fixture.session.bridge.seesTarget = { _, _ in sees }
        #expect(fixture.session.bridge.queueLineOfSightEvents() == 0)
        sees = true
        #expect(fixture.session.bridge.queueLineOfSightEvents() == 1)
        #expect(fixture.session.bridge.queueLineOfSightEvents() == 0)
        PapyrusWorldFixture.drain(world)
        #expect(fixture.session.dispatch.notes == ["gain"])
        #expect(register("RegisterForLOS") == .returned(.none))
        #expect(register("UnregisterForLOS") == .returned(.none))
        #expect(fixture.session.bridge.queueLineOfSightEvents() == 0)
    }
}
