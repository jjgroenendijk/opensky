// The Game menu natives reach the menu bridge, and fail without one.

import FeaturesTesting
import FormatsTesting
import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
@testable import OpenSkyScriptingInterface
import OpenSkyWorldInterface
import OpenSkyWorldState
import Testing

@MainActor
private final class FakeMenuBridge: PapyrusMenuBridge {
    var calls: [String] = []
    var races: [ReferenceKey: FormID] = [:]

    func showRaceMenu(limited: Bool) {
        calls.append("race(\(limited))")
    }

    func fastTravel(to marker: ReferenceKey) -> Bool {
        true
    }

    func setFastTravelEnabled(_ enabled: Bool) {
        calls.append("travel(\(enabled))")
    }

    func addToMap(_ marker: ReferenceKey, allowFastTravel: Bool) {}

    func isMapMarkerVisible(_ marker: ReferenceKey) -> Bool {
        false
    }

    func race(of actor: ReferenceKey) -> FormID? {
        races[actor]
    }

    func sex(ofBase base: FormID) -> Int? {
        nil
    }

    func name(of form: FormID) -> String? {
        nil
    }

    func movePlayer(to target: ReferenceKey) {
        calls.append("move(\(target))")
    }
}

@MainActor
struct PapyrusNativeMenusTests {
    private static func game(
        _ name: String, _ arguments: [PapyrusValue] = []
    ) -> PapyrusNativeCall {
        PapyrusNativeCall(
            kind: .staticFunction, scriptName: "Game", functionName: name, receiver: nil,
            arguments: arguments, returnType: .none
        )
    }

    @Test func gameNativesReachTheBridge() {
        let menus = FakeMenuBridge()
        let bridge = PapyrusWorldStateBridge(worldState: WorldStateStore())
        bridge.menus = menus
        var registry = PapyrusNativeRegistry(context: PapyrusNativeContext(world: bridge))
        PapyrusNativeFunctions.installMenus(into: &registry)
        #expect(registry.invoke(Self.game("ShowRaceMenu")) == .returned(.none))
        #expect(registry.invoke(Self.game("ShowLimitedRaceMenu")) == .returned(.none))
        let enable = Self.game("EnableFastTravel", [.boolean(false)])
        #expect(registry.invoke(enable) == .returned(.none))
        #expect(menus.calls == ["race(false)", "race(true)", "travel(false)"])
    }

    @Test func withoutTheBridgeANativeDoesNothing() {
        var registry = PapyrusNativeRegistry(context: PapyrusNativeContext())
        PapyrusNativeFunctions.installMenus(into: &registry)
        #expect(registry.invoke(Self.game("ShowRaceMenu")) != .returned(.none))
    }

    @Test func actorBaseAndRaceAnswerForAnyReference() throws {
        let fixture = try PapyrusNativeReferenceFixture.make()
        let menus = FakeMenuBridge()
        menus.races[fixture.key] = FormID(0x100)
        fixture.session.bridge.menus = menus
        let actor = { (name: String) in
            fixture.registry.invoke(PapyrusWorldFixture.methodCall(
                "Actor", name, receiver: fixture.receiver, returnType: .object("Form")
            ))
        }
        let base = fixture.call("GetBaseObject", returnType: .object("Form"))
        #expect(actor("GetActorBase") == base)
        #expect(actor("GetLeveledActorBase") == base)
        #expect(actor("GetRace") == base)
        menus.races = [:]
        #expect(actor("GetRace") == .returned(.none))
    }

    /// A placed actor is an `ACHR`, not a `REFR`, and still names its NPC base.
    @Test func actorBaseAnswersForAPlacedActor() throws {
        let entry = try PapyrusWorldFixture.actorEntry(
            objectID: 0x900, base: 0x50, scripts: [.init("Horse", properties: [])]
        )
        let session = PapyrusWorldFixture.session(
            objects: [PapyrusWorldFixture.eventScript("Horse", events: [])], entries: [entry]
        )
        let menus = FakeMenuBridge()
        session.bridge.menus = menus
        let registry = PapyrusWorldFixture.registry(for: session)
        let result = registry.invoke(PapyrusWorldFixture.methodCall(
            "Actor", "GetActorBase", receiver: session.world.objectHandle(for: entry.key),
            returnType: .object("ActorBase")
        ))
        let base = ReferenceKey.plugin(name: PapyrusWorldFixture.pluginName, objectID: 0x50)
        #expect(result == .returned(.object(session.world.objectHandle(for: base))))
    }

    @Test func moveToPlacesAResidentReferenceAtItsTarget() throws {
        let fixture = try PapyrusNativeReferenceFixture.make()
        let menus = FakeMenuBridge()
        fixture.session.bridge.menus = menus
        let move = { (target: PapyrusObjectHandle, offset: PapyrusValue) in
            fixture.registry.invoke(PapyrusWorldFixture.methodCall(
                "ObjectReference", "MoveTo", receiver: fixture.receiver,
                arguments: [.object(target), offset, .float(0), .float(5)]
            ))
        }
        #expect(move(fixture.receiver, .integer(10)) == .returned(.none))
        let written = try #require(fixture.session.worldState.component(
            ReferenceTransformOverride.self, for: fixture.key
        ))
        #expect(written.position == SIMD3<Float>(11, 2, 8))
        #expect(menus.calls.isEmpty)
        #expect(PapyrusWorldFixture.isInvalidArguments(move(fixture.receiver, .float(.infinity))))
        let absent = fixture.handle(PapyrusNativeReferenceFixture.doorID)
        #expect(PapyrusWorldFixture.isInvalidArguments(move(absent, .float(0))))
    }

    @Test func moveToSendsAnUnloadedReferenceIntoTheTargetCell() throws {
        let fixture = try PapyrusNativeReferenceFixture.make()
        let menus = FakeMenuBridge()
        fixture.session.bridge.menus = menus
        let prisoner = PapyrusNativeReferenceFixture.key(PapyrusNativeReferenceFixture.doorID)
        let record = try PapyrusWorldFixture.referenceEntry(
            objectID: PapyrusNativeReferenceFixture.doorID, scripts: [], placement: SIMD3(9, 9, 9)
        )
        fixture.session.references.pluginPlacements[prisoner] = PluginPlacement(
            entry: record, home: .interior(FormID(0x999))
        )
        let result = fixture.registry.invoke(PapyrusWorldFixture.methodCall(
            "ObjectReference", "MoveTo",
            receiver: fixture.handle(PapyrusNativeReferenceFixture.doorID),
            arguments: [.object(fixture.receiver), .float(0), .float(0), .float(0)]
        ))
        #expect(result == .returned(.none))
        let store = fixture.session.worldState
        #expect(store.component(ReferenceTransformOverride.self, for: prisoner)?.position == SIMD3(
            1,
            2,
            3
        ))
        #expect(
            store.component(ReferenceRelocation.self, for: prisoner)
                == ReferenceRelocation(location: PapyrusWorldFixture.cell)
        )
        #expect(menus.calls.isEmpty)
    }
}
