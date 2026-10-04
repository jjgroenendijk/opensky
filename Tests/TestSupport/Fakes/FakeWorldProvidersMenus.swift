// `FakeWorldProviders`' title, race, and map menu seams: a recorder that keeps
// the calls, so a panel click and a registry reset are observed alike.

import AppKit
@testable import OpenSkyMenus

@MainActor
final class FakeMenuCalls {
    var calls: [String] = []
    var titleOpen = false
    var titleMovie = true
    var raceOpen = false
    var mapMode: String?
}

extension FakeWorldProviders {
    var titleMenuSnapshot: TitleMenuSnapshot {
        TitleMenuSnapshot(
            isOpen: menuCalls.titleOpen, rows: ["New", "Load", "Quit"], selectedIndex: 0,
            isLoadPageOpen: false, lastResult: nil,
            movie: TitleMenuMovieSnapshot(isEnabled: menuCalls.titleMovie)
        )
    }

    func setTitleMenuMovieEnabled(_ enabled: Bool) {
        menuCalls.titleMovie = enabled
        menuCalls.calls.append("title.movie(\(enabled))")
    }

    func openTitleMenu() {
        menuCalls.titleOpen = true
        menuCalls.calls.append("title.open")
    }

    func closeTitleMenu() {
        menuCalls.titleOpen = false
        menuCalls.calls.append("title.close")
    }

    func sendTitleMenuInput(_ event: MenuInputEvent) {
        menuCalls.calls.append("title.\(event)")
    }

    var raceMenuSnapshot: RaceMenuSnapshot {
        RaceMenuSnapshot(
            isOpen: menuCalls.raceOpen, isLimited: false, isEditingName: false,
            rows: ["Race: Nord", "Sex: Male"], selectedIndex: 0, lastResult: nil
        )
    }

    func openRaceMenu(limited: Bool) {
        menuCalls.raceOpen = true
        menuCalls.calls.append("race.open(\(limited))")
    }

    func sendRaceMenuInput(_ event: MenuInputEvent) {
        if event == .button(.cancel) {
            menuCalls.raceOpen = false
        }
        menuCalls.calls.append("race.\(event)")
    }

    func resetPlayerIdentity() {
        menuCalls.calls.append("race.reset")
    }

    func setRaceMenuName(_ name: String) {
        menuCalls.calls.append("race.name(\(name))")
    }

    var mapMenuSnapshot: MapMenuSnapshot {
        MapMenuSnapshot(
            mode: menuCalls.mapMode, markerCount: 2, visibleCount: 1, discoveredCount: 1,
            selected: "Riverwood", cameraHeight: nil,
            cameraPitch: nil, questTargets: [], fastTravelEnabled: true, lastResult: nil
        )
    }

    func openMap(local: Bool) {
        menuCalls.mapMode = local ? "local" : "world"
        menuCalls.calls.append("map.open(\(local))")
    }

    func revealAllMapMarkers() {
        menuCalls.calls.append("map.revealAll")
    }

    func resetLocalMapFog() {
        menuCalls.calls.append("map.resetFog")
    }

    func closeMap() {
        menuCalls.mapMode = nil
        menuCalls.calls.append("map.close")
    }

    func zoomMap(by amount: Float) {
        menuCalls.calls.append("map.zoom(\(Int(amount)))")
    }

    func tiltMap(by degrees: Float) {
        menuCalls.calls.append("map.tilt(\(Int(degrees)))")
    }

    func sendMapInput(_ event: MenuInputEvent) {
        menuCalls.calls.append("map.\(event)")
    }
}
