// A view of the world map, the local map, and fast travel.

import Foundation

nonisolated public struct MapMenuSnapshot: Equatable, Sendable {
    public let selected: String?
    public let cameraHeight: Float?
    public let questTargets: [String]
    public let lastResult: String?
    public let inspectedMarker: String?

    public init(
        selected: String?, cameraHeight: Float?,
        questTargets: [String], lastResult: String?,
        inspectedMarker: String? = nil
    ) {
        self.inspectedMarker = inspectedMarker
        self.selected = selected
        self.cameraHeight = cameraHeight
        self.questTargets = questTargets
        self.lastResult = lastResult
    }
}
