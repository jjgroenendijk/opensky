// The sidebar's view of the world map, the local map, and fast travel.

import Foundation

nonisolated public struct MapMenuSnapshot: Equatable, Sendable {
    public let mode: String?
    public let markerCount: Int
    public let visibleCount: Int
    public let discoveredCount: Int
    public let selected: String?
    public let cameraHeight: Float?
    public let cameraPitch: Float?
    public let questTargets: [String]
    public let fastTravelEnabled: Bool
    public let lastResult: String?
    public let inspectedMarker: String?

    public init(
        mode: String?, markerCount: Int, visibleCount: Int, discoveredCount: Int,
        selected: String?, cameraHeight: Float?, cameraPitch: Float?,
        questTargets: [String], fastTravelEnabled: Bool, lastResult: String?,
        inspectedMarker: String? = nil
    ) {
        self.inspectedMarker = inspectedMarker
        self.mode = mode
        self.markerCount = markerCount
        self.visibleCount = visibleCount
        self.discoveredCount = discoveredCount
        self.selected = selected
        self.cameraHeight = cameraHeight
        self.cameraPitch = cameraPitch
        self.questTargets = questTargets
        self.fastTravelEnabled = fastTravelEnabled
        self.lastResult = lastResult
    }
}

public protocol MapMenuControlProviding: AnyObject {
    /// Gives keyboard focus back to the game view after a panel button.
    func refocusGameView()
    var mapMenuSnapshot: MapMenuSnapshot { get }
    func openMap(local: Bool)
    func closeMap()
    func zoomMap(by amount: Float)
    func tiltMap(by degrees: Float)
    func sendMapInput(_ event: MenuInputEvent)
    func revealAllMapMarkers()
    func resetLocalMapFog()
    func inspectMapWorldspace(offset: Int)
    func inspectMapMarker(offset: Int)
    func applyToInspectedMarker(_ action: MapMarkerAction)
}

/// Lets the app's provider object stand in for its `MapMenuCoordinator`.
public protocol MapMenuControlForwarding: MapMenuControlProviding {
    var mapMenu: MapMenuCoordinator { get }
}

extension MapMenuControlForwarding {
    public var mapMenuSnapshot: MapMenuSnapshot {
        mapMenu.snapshot
    }

    public func openMap(local: Bool) {
        mapMenu.open(local ? .local : .world)
    }

    public func closeMap() {
        mapMenu.close()
    }

    public func zoomMap(by amount: Float) {
        mapMenu.zoom(by: amount)
    }

    public func tiltMap(by degrees: Float) {
        mapMenu.tilt(by: degrees)
    }

    public func sendMapInput(_ event: MenuInputEvent) {
        mapMenu.route(event)
    }

    public func revealAllMapMarkers() {
        mapMenu.revealAll()
    }

    public func resetLocalMapFog() {
        mapMenu.resetFog()
    }

    public func inspectMapWorldspace(offset: Int) {
        mapMenu.inspectWorldspace(offset: offset)
    }

    public func inspectMapMarker(offset: Int) {
        mapMenu.inspectMarker(offset: offset)
    }

    public func applyToInspectedMarker(_ action: MapMarkerAction) {
        mapMenu.apply(action)
    }
}
