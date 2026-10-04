// The race menu rules and its shell over the real menu stack and a fake world.

import OpenSkyActorsInterface
import OpenSkyFormatsESM
@testable import OpenSkyMenus
import Testing

@MainActor
private final class FakeRaceMenuWorld: RaceMenuWorld, MenuInputConsumer {
    var playerIdentity: PlayerIdentityState? = PlayerIdentityState(
        race: FormID(0x13746), isFemale: false, name: "Prisoner"
    )
    let recordIdentity: PlayerIdentityState? = PlayerIdentityState(
        race: FormID(0x13748), isFemale: true, name: "Record"
    )
    let playableRaces = [
        RaceChoice(formID: FormID(0x13746), name: "Nord"),
        RaceChoice(formID: FormID(0x13748), name: "Redguard")
    ]
    var applied: [PlayerIdentityState] = []
    var closedCount = 0

    func applyPlayerIdentity(_ identity: PlayerIdentityState) {
        applied.append(identity)
    }

    func raceMenuClosed() {
        closedCount += 1
    }

    var menuInputConsumer: (any MenuInputConsumer)? {
        self
    }

    func handleMenuInput(_ event: MenuInputEvent) {}
}

struct RaceMenuCoordinatorTests {
    private static let identity = PlayerIdentityState(
        race: FormID(0x13746), isFemale: false, name: "Prisoner"
    )
    private static let races = [
        RaceChoice(formID: FormID(0x13746), name: "Nord"),
        RaceChoice(formID: FormID(0x13748), name: "Redguard")
    ]

    @Test
    func fullMenuStepsRaceSexSlidersAndParts() {
        var model = RaceMenuModel(identity: Self.identity, races: Self.races, limited: false)
        #expect(model.identity.face.morphs.count == 19, "short NAM9 pads to 19")
        #expect(model.rows.first == .race)
        #expect(model.rows.last == .name)
        model.step(.race, by: 1)
        #expect(model.identity.race == FormID(0x13748))
        model.step(.race, by: 1)
        #expect(model.identity.race == FormID(0x13746), "the race list wraps")
        model.step(.sex, by: 1)
        #expect(model.identity.isFemale)
        for _ in 0 ..< 15 {
            model.step(.slider(0), by: 1)
        }
        #expect(model.identity.face.morphs[0] == 1, "sliders clamp at 1")
        model.step(.part(0), by: -1)
        #expect(model.identity.face.parts[0] == 0, "parts clamp at 0")
        model.step(.weight, by: 20)
        #expect(model.identity.face.weight == 100)
    }

    @Test
    func limitedMenuHidesNameAndSexAndLocksTheRace() {
        var model = RaceMenuModel(identity: Self.identity, races: Self.races, limited: true)
        #expect(!model.rows.contains(.sex))
        #expect(!model.rows.contains(.name))
        model.moveSelection(by: 1)
        #expect(model.raceLocked)
        #expect(!model.rows.contains(.race))
        model.setName("Other")
        #expect(model.identity.name == "Prisoner")
    }

    @Test @MainActor
    func coordinatorTypesTheNameAndAppliesOnClose() {
        let menuMode = MenuModeController()
        let world = FakeRaceMenuWorld()
        let menu = RaceMenuCoordinator(menuMode: menuMode)
        menu.attach(world: world)
        #expect(menu.open(limited: false))
        #expect(menuMode.topMenu == RaceMenuCoordinator.identifier)
        menu.route(.move(.up))
        menu.route(.button(.accept))
        #expect(menu.isEditingName)
        #expect(menu.type("\u{7F}\u{7F}\u{7F}\u{7F}\u{7F}\u{7F}\u{7F}\u{7F}Ada"))
        menu.route(.button(.accept))
        #expect(!menu.isEditingName)
        #expect(!menu.type("x"), "text goes elsewhere when not editing")
        menu.route(.button(.cancel))
        #expect(!menu.isOpen)
        #expect(!menuMode.isMenuMode)
        #expect(world.applied.map(\.name) == ["Ada"])
        #expect(world.closedCount == 1)
        #expect(menu.snapshot.lastResult == "Ada, Nord, Male")
    }

    @Test @MainActor
    func openWithoutAnIdentityFails() {
        let world = FakeRaceMenuWorld()
        world.playerIdentity = nil
        let menu = RaceMenuCoordinator(menuMode: MenuModeController())
        menu.attach(world: world)
        #expect(!menu.open(limited: true))
    }

    @Test @MainActor
    func resetAppliesTheRecordIdentityOnlyWhileClosed() {
        let world = FakeRaceMenuWorld()
        let menu = RaceMenuCoordinator(menuMode: MenuModeController())
        menu.attach(world: world)
        menu.open(limited: false)
        menu.resetToRecord()
        #expect(world.applied.isEmpty, "the open menu owns the identity")
        menu.close()
        world.applied.removeAll()
        menu.resetToRecord()
        #expect(world.applied.map(\.name) == ["Record"])
        #expect(menu.snapshot.lastResult == "Reset to the Player record")
    }
}
