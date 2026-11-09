// What the last map control did, as a value. A fast-travel refusal reads the load
// order's own notice, so the formatter asks for it.

public import OpenSkyMenusInterface

nonisolated public enum MapMenuOutcome: Equatable, Sendable {
    case markersRevealed(Int)
    case fogReset
    case travelRefused(FastTravelRefusal)
    case travelled(String)
    case travelFailed
    case noQuestTarget
    case showingQuestTarget(String)
    case mapDidNotOpen
    case markerSet(String, MapMarkerAction)
    /// The `sPlaceMarker` text and where the custom marker went.
    case playerMarkerPlaced(String, SIMD3<Float>)
    /// The button the player picked, such as Remove It.
    case playerMarkerAnswered(String)
    case playerMarkerNeedsWorldMap

    public func text(refusal: (FastTravelRefusal) -> String) -> String {
        switch self {
        case let .markersRevealed(count): "Markers revealed: \(count)"
        case .fogReset: "Fog reset"
        case let .travelRefused(reason): refusal(reason)
        case let .travelled(name): "Travelled to \(name)"
        case .travelFailed: "Travel failed"
        case .noQuestTarget: "No quest target to show"
        case let .showingQuestTarget(text): "Showing \(text)"
        case .mapDidNotOpen: "Map did not open"
        case let .markerSet(name, action): "\(name): \(action.rawValue)"
        case let .playerMarkerPlaced(text, point): "\(text): \(Int(point.x)), \(Int(point.y))"
        case let .playerMarkerAnswered(button): button
        case .playerMarkerNeedsWorldMap: "The custom marker needs the world map"
        }
    }
}
