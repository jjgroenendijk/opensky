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

extension MapMenuCoordinator: MapMenuControlProviding {
    public var mapMenuSnapshot: MapMenuSnapshot {
        snapshot
    }

    public func openMap(local: Bool) {
        open(local ? .local : .world)
    }

    public func closeMap() {
        close()
    }

    public func zoomMap(by amount: Float) {
        zoom(by: amount)
    }

    public func tiltMap(by degrees: Float) {
        tilt(by: degrees)
    }

    public func sendMapInput(_ event: MenuInputEvent) {
        route(event)
    }

    public func revealAllMapMarkers() {
        revealAll()
    }

    public func resetLocalMapFog() {
        resetFog()
    }

    public func inspectMapWorldspace(offset: Int) {
        inspectWorldspace(offset: offset)
    }

    public func inspectMapMarker(offset: Int) {
        inspectMarker(offset: offset)
    }

    public func applyToInspectedMarker(_ action: MapMarkerAction) {
        apply(action)
    }
}
