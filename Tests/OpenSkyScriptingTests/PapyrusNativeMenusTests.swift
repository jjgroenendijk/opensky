// The Game menu natives reach the menu bridge, and fail without one.

import Foundation
import OpenSkyFormatsESM
@testable import OpenSkyScripting
@testable import OpenSkyScriptingInterface
import OpenSkyWorldState
import Testing

@MainActor
private final class FakeMenuBridge: PapyrusMenuBridge {
    var calls: [String] = []

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
        nil
    }

    func sex(ofBase base: FormID) -> Int? {
        nil
    }

    func name(of form: FormID) -> String? {
        nil
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
}
