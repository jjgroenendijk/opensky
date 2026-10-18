// The book bar, the name field, and the offline Creation Club screen: their movie
// contracts on synthetic objects, and their text panels driven by keys.

import Foundation
import OpenSkyFormatsSWF
@testable import OpenSkyMenus
import Testing

@MainActor
struct SmallMenuMovieTests {
    private static func function(_ name: String, of object: AS2Object) -> AS2Value? {
        object.lookup(name)?.property.value
    }

    @Test func theBookBarShowsTheStealButton() throws {
        let runtime = try MenuMovieCallLog.emptyRuntime()
        let log = MenuMovieCallLog(runtime: runtime, names: ["InitExtensions", "ShowTakeButton"])
        BookMenuBarMovieBridge.activate(runtime: runtime, take: .steal)
        #expect(log.names == ["InitExtensions", "ShowTakeButton"])
        #expect(log.arguments(of: "ShowTakeButton") == [.boolean(true), .boolean(true)])
    }

    @Test func theNameFieldListenerReportsAcceptAndCancel() throws {
        let runtime = try MenuMovieCallLog.emptyRuntime()
        let clip = runtime.runtime.makeObject()
        var listener: (scope: AS2Object, method: String)?
        AS2Natives.method(runtime.runtime, on: clip, name: "addEventListener") { context in
            if
                case .string("nameChange") = context.argument(0),
                let scope = context.argument(1).objectValue,
                case let .string(method) = context.argument(2) {
                MainActor.assumeIsolated { listener = (scope, method) }
            }
            return .undefined
        }
        let results = MenuMovieEventLog<Bool>()
        TextEntryMenuMovieBridge.listen(on: clip, runtime: runtime) { results.append($0) }
        let found = try #require(listener)
        let callback = try #require(Self.function(found.method, of: found.scope))
        for accepted in [true, false] {
            let event = runtime.runtime.makeObject()
            event.define(.string("nameChange"), for: "type")
            event.define(.boolean(accepted), for: "nameChanged")
            runtime.runtime.invoke(
                callback, thisValue: .object(found.scope), arguments: [.object(event)]
            )
        }
        #expect(results.events == [true, false])
    }

    @Test func theNameFieldPanelTypesAcceptsAndCancels() {
        let menuMode = MenuModeController()
        let menu = TextEntryMenuCoordinator(menuMode: menuMode, world: FakeMenuScreenWorld())
        var finished: [String?] = []
        #expect(menu.open(title: "Name") { finished.append($0) })
        #expect(menu.type("Abc\u{7F}"))
        #expect(menu.text == "Ab")
        menu.route(.button(.accept))
        #expect(finished == ["Ab"])
        #expect(!menu.isOpen)
        #expect(!menu.type("x"))
        #expect(menu.open(title: "Name") { finished.append($0) })
        menu.route(.button(.accept))
        #expect(menu.isOpen)
        menu.route(.button(.cancel))
        #expect(finished == ["Ab", nil])
        #expect(menu.lastResult == "Cancelled")
        #expect(menuMode.topMenu == nil)
    }

    @Test func theStoreCallsDoNothingAndClosingCloses() throws {
        let runtime = try MenuMovieCallLog.emptyRuntime()
        let codeObject = runtime.runtime.makeObject()
        let events = MenuMovieEventLog<CreationClubMovieEvent>()
        CreationClubMenuMovieBridge.fill(codeObject, runtime: runtime.runtime) {
            events.append($0)
        }
        for name in ["InitCreationClubMenu", "PurchaseMod", "PlaySound", "confirmCloseManager"] {
            let callee = try #require(Self.function(name, of: codeObject))
            runtime.runtime.invoke(callee, thisValue: .object(codeObject), arguments: [])
        }
        #expect(events.events == [.close])
    }

    @Test func theCreationClubPanelClosesOnCancel() {
        let menuMode = MenuModeController()
        let menu = CreationClubMenuCoordinator(menuMode: menuMode, world: FakeMenuScreenWorld())
        #expect(menu.open())
        #expect(menuMode.topMenu == CreationClubMenuCoordinator.identifier)
        menu.route(.button(.accept))
        #expect(menu.isOpen)
        menu.route(.button(.cancel))
        #expect(!menu.isOpen)
    }
}
