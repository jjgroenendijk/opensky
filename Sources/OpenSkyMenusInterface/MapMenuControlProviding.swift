import Foundation

nonisolated public struct MapMenuSnapshot: Equatable, Sendable {
    public let selected: String?
    public let cameraHeight: Float?
    public let questTargets: [String]
    public let lastResult: String?
    public let inspectedMarker: String?
    /// The custom marker in the map's worldspace, such as "Custom Destination at 10, 20".
    public let playerMarker: String?

    public init(
        selected: String?, cameraHeight: Float?,
        questTargets: [String], lastResult: String?,
        inspectedMarker: String? = nil,
        playerMarker: String? = nil
    ) {
        self.playerMarker = playerMarker
        self.inspectedMarker = inspectedMarker
        self.selected = selected
        self.cameraHeight = cameraHeight
        self.questTargets = questTargets
        self.lastResult = lastResult
    }
}
