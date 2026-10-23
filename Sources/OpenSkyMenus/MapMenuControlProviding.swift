// A view of the world map, the local map, and fast travel.

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
