// The trap natives that move or fire things: `SetMotionType`, `Reset`, `Weapon.Fire`,
// and the stagger of `ProcessTrapHit`.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
@testable import OpenSkyScriptingInterface
import OpenSkyWorldState
import Testing

@MainActor
struct PapyrusNativeTrapMotionTests {
    private typealias Fixture = PapyrusNativeReferenceFixture

    @Test func setMotionTypeMapsThePapyrusValues() throws {
        let fixture = try Fixture.make()
        let trapWorld = FakeTrapWorld()
        fixture.session.bridge.trapWorld = trapWorld
        #expect(fixture.call("SetMotionType", arguments: [.integer(4), .boolean(true)])
            == .returned(.none))
        #expect(trapWorld.motionTypes[fixture.key] == .keyframed)
        _ = fixture.call("SetMotionType", arguments: [.integer(3), .boolean(true)])
        #expect(trapWorld.motionTypes[fixture.key] == .dynamic)
        #expect(PapyrusWorldFixture.isInvalidArguments(
            fixture.call("SetMotionType", arguments: [.integer(7), .boolean(true)])
        ))
        #expect(trapWorld.motionTypes[fixture.key] == .dynamic)
    }

    @Test func resetPassesTheTargetAndStaysAStubForAnActor() throws {
        let fixture = try Fixture.make()
        let trapWorld = FakeTrapWorld()
        fixture.session.bridge.trapWorld = trapWorld
        let door = fixture.handle(Fixture.doorID)
        #expect(fixture.call("Reset", arguments: [.none]) == .returned(.none))
        #expect(fixture.call("Reset", arguments: [.object(door)]) == .returned(.none))
        #expect(trapWorld.resets.map(\.target) == [nil, Fixture.key(Fixture.doorID)])
        trapWorld.resetsReferences = false
        #expect(fixture.call("Reset", arguments: [.none]) == .deviated(.none, .stubbed))
    }

    @Test func fireShootsTheReceiverWeaponFromTheSource() throws {
        let fixture = try Fixture.make()
        let trapWorld = FakeTrapWorld()
        let weapon = fixture.handle(Fixture.keywordID)
        let ammunition = fixture.handle(Fixture.otherKeywordID)
        let fire = {
            fixture.registry.invoke(PapyrusWorldFixture.methodCall(
                "Weapon", "Fire", receiver: weapon,
                arguments: [.object(fixture.receiver), .object(ammunition)]
            ))
        }
        #expect(fire() == .deviated(.none, .stubbed))
        fixture.session.bridge.trapWorld = trapWorld
        #expect(fire() == .returned(.none))
        #expect(trapWorld.shots.first?.weapon == Fixture.key(Fixture.keywordID))
        #expect(trapWorld.shots.first?.source == fixture.key)
        #expect(trapWorld.shots.first?.ammunition == Fixture.key(Fixture.otherKeywordID))
    }

    @Test func trapHitStaggersAndPushesTheActorHit() throws {
        let fixture = try Fixture.make()
        let trapWorld = FakeTrapWorld()
        fixture.session.bridge.trapWorld = trapWorld
        let hit = PapyrusWorldFixture.methodCall(
            "ObjectReference", "ProcessTrapHit", receiver: fixture.receiver,
            arguments: [.object(fixture.receiver), .float(10), .float(300)]
                + [PapyrusValue](repeating: .float(0), count: 6) + [.integer(0), .float(2)]
        )
        PapyrusNativeFunctions.pushBack(hit, world: fixture.session.bridge, actor: .player)
        #expect(trapWorld.staggers.first?.actor == .player)
        #expect(trapWorld.staggers.first?.magnitude == 1)
        #expect(trapWorld.pushes.first?.source == fixture.key)
        #expect(trapWorld.pushes.first?.speed == 300)
        #expect(trapWorld.pushes.first?.direction == nil)
    }
}
