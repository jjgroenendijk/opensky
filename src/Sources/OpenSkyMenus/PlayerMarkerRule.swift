// The player's own map marker: what the place key aims at, and which question it asks.
// See docs/engine/world-map.md#custom-marker.

import Foundation
public import OpenSkyGameData
public import OpenSkyMenusInterface
import OpenSkyWorldInterface
import simd

/// The words of the custom marker's questions and its name.
nonisolated public enum PlayerMarkerText: String, GameSettingTextKey {
    case placeMarker = "sPlaceMarker"
    case placeUndiscovered = "sPlaceMarkerUndiscovered"
    case moveQuestion = "sMoveMarkerQuestion"
    case move = "sMoveMarker"
    case remove = "sRemoveMarker"
    case leave = "sLeaveMarker"
    case name = "sPlayerSetMarkerName"
    case yes = "sYesText"
    case no = "sNoText"

    public var fallback: String {
        switch self {
        case .placeMarker: "Place Marker"
        case .placeUndiscovered: "You have not discovered this location yet.\nPlace marker?"
        case .moveQuestion: "Do you want to move your marker or remove it?"
        case .move: "Move It"
        case .remove: "Remove It"
        case .leave: "Leave It"
        case .name: "Custom Destination"
        case .yes: "Yes"
        case .no: "No"
        }
    }
}

/// Where the place key puts the marker.
nonisolated public enum PlayerMarkerTarget: Equatable, Sendable {
    /// The ground under the map centre.
    case ground(SIMD3<Float>)
    /// A location marker near the map centre; the custom marker goes on it.
    case site(MapMarkerSite)

    public var position: SIMD3<Float> {
        switch self {
        case let .ground(point): point
        case let .site(site): site.position
        }
    }
}

/// The step the place key takes.
nonisolated public enum PlayerMarkerStep: Equatable, Sendable {
    case place(SIMD3<Float>)
    /// `sPlaceMarkerUndiscovered` with Yes and No.
    case askUndiscovered(SIMD3<Float>)
    /// `sMoveMarkerQuestion` with Move It, Remove It, and Leave It.
    case askMoveOrRemove
}

/// The answers to `sMoveMarkerQuestion`, in button order.
nonisolated enum PlayerMarkerMoveAnswer: Int, CaseIterable, Sendable {
    case move, remove, leave
}

nonisolated public enum PlayerMarkerRule {
    /// A marker this close to the map centre, as a share of the camera height, is aimed at.
    public static let pickShare: Float = 0.05

    public static func target(
        focus: SIMD2<Float>, cameraHeight: Float, nearest: MapMarkerSite?
    ) -> PlayerMarkerTarget {
        let ground = PlayerMarkerTarget.ground(SIMD3(focus.x, focus.y, 0))
        guard let nearest else { return ground }
        let flat = SIMD2(nearest.position.x, nearest.position.y)
        return simd_distance(flat, focus) <= cameraHeight * pickShare ? .site(nearest) : ground
    }

    /// `hasMarker` asks first whether to move or remove the marker that is placed.
    public static func step(_ target: PlayerMarkerTarget, hasMarker: Bool) -> PlayerMarkerStep {
        if hasMarker {
            return .askMoveOrRemove
        }
        if case let .site(site) = target, !site.state.isDiscovered {
            return .askUndiscovered(site.position)
        }
        return .place(target.position)
    }
}
