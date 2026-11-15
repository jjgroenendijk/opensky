// The Tween menu: it needs a game, the arrows pick the entry that sits that way, an
// entry opens its menu after the Tween menu shuts, and the movie's calls drive the same.

import Foundation
import OpenSkyFormatsSWF
@testable import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyRenderCore
import OpenSkyRendering
import Testing

@MainActor
final class FakeTweenWorld: TweenMenuWorld, MenuInputConsumer {
    var renderer: (any RendererPort)? {
        nil
    }

    var viewCamera: FreeFlyCamera? {
        nil
    }

    var uiScene = UIScene.empty
    var gameDateText: String? = "Sundas, 1:00 PM, 17th of Last Seed, 4E 201"
    var tweenLevel = TweenMenuLevel(level: 3, progress: 0.25, levelUpReady: false)

    func showHUDNotification(_: String) {}

    var menuInputConsumer: (any MenuInputConsumer)? {
        self
    }

    func handleMenuInput(_: MenuInputEvent) {}
}

@MainActor
struct TweenMenuCoordinatorTests {
    @Test func theMenuNeedsAGame() {
        let world = FakeTweenWorld()
        world.gameDateText = nil
        let menu = TweenMenuCoordinator(menuMode: MenuModeController(), world: world)
        #expect(!menu.open { _ in })
        #expect(menu.lastResult == "Not opened: no game")
    }

    @Test func anEntryOpensItsMenuAfterTheTweenMenuShuts() {
        let world = FakeTweenWorld()
        let menuMode = MenuModeController()
        let menu = TweenMenuCoordinator(menuMode: menuMode, world: world)
        var chosen: [TweenMenuChoice] = []
        var topWhenChosen: MenuIdentifier?
        #expect(menu.open { choice in
            chosen.append(choice)
            topWhenChosen = menuMode.topMenu
        })
        #expect(menuMode.topMenu == TweenMenuCoordinator.identifier)
        #expect(menuMode.isWorldSimPaused)
        menu.route(.button(.accept))
        #expect(chosen.isEmpty, "nothing is highlighted yet")
        menu.route(.move(.left))
        #expect(menu.highlighted == .magic)
        menu.route(.button(.accept))
        #expect(chosen == [.magic])
        #expect(topWhenChosen == nil)
        #expect(!menu.isOpen)
        #expect(menu.lastResult == "Opened magic")
    }

    @Test func eachArrowPicksTheEntryThatSitsThatWay() {
        #expect(TweenMenuCoordinator.choice(toward: .up) == .skills)
        #expect(TweenMenuCoordinator.choice(toward: .left) == .magic)
        #expect(TweenMenuCoordinator.choice(toward: .right) == .items)
        #expect(TweenMenuCoordinator.choice(toward: .down) == .map)
    }

    @Test func cancelShutsTheMenuWithoutAMovie() {
        let world = FakeTweenWorld()
        let menuMode = MenuModeController()
        let menu = TweenMenuCoordinator(menuMode: menuMode, world: world)
        #expect(menu.open { _ in Issue.record("cancel chose an entry") })
        menu.route(.button(.cancel))
        #expect(!menu.isOpen)
        #expect(menuMode.topMenu == nil)
        #expect(menu.lastResult == "Closed")
    }

    @Test func theMovieCallsDriveTheMenu() {
        let world = FakeTweenWorld()
        world.tweenLevel.levelUpReady = true
        let menu = TweenMenuCoordinator(menuMode: MenuModeController(), world: world)
        var chosen: [TweenMenuChoice] = []
        menu.open { chosen.append($0) }
        #expect(menu.showsLevelUp)
        menu.handle(.highlight(.map))
        #expect(menu.highlighted == .map)
        menu.handle(.closing)
        #expect(menu.isClosing)
        menu.handle(.open(.map))
        #expect(chosen.isEmpty, "an entry does not open while the menu closes")
        menu.handle(.closed)
        #expect(!menu.isOpen)
        #expect(!menu.isClosing)
    }

    @Test func theMovieNumbersEachEntry() {
        #expect(TweenMenuMovieBridge.choice(.number(1)) == .skills)
        #expect(TweenMenuMovieBridge.choice(.number(4)) == .map)
        #expect(TweenMenuMovieBridge.choice(.number(0)) == nil)
        #expect(TweenMenuMovieBridge.choice(.string("2")) == nil)
    }
}
