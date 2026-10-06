// The sidebar's marker inspector: pick a worldspace and one of its markers,
// then reveal, discover, or hide that marker alone.

import Foundation
import OpenSkyFormatsESM
import OpenSkyWorldInterface

/// A worldspace that has map markers, for the inspector's picker.
nonisolated public struct MapWorldspaceChoice: Equatable, Sendable {
    public let formID: ResolvedFormID
    public let name: String

    public init(formID: ResolvedFormID, name: String) {
        self.formID = formID
        self.name = name
    }
}

nonisolated public enum MapMarkerAction: String, CaseIterable, Sendable {
    /// Shown on the map and compass, not yet a travel target.
    case reveal
    /// Shown, discovered, and a travel target, as walking up to it does.
    case discover
    /// Gone from the map and compass, as before the player heard of it.
    case hide

    public var state: MapMarkerState {
        switch self {
        case .reveal: MapMarkerState(isVisible: true, isDiscovered: false, canTravelTo: false)
        case .discover: MapMarkerState(isVisible: true, isDiscovered: true, canTravelTo: true)
        case .hide: MapMarkerState(isVisible: false, isDiscovered: false, canTravelTo: false)
        }
    }
}

extension MapMenuCoordinator {
    public func inspectWorldspace(offset: Int) {
        guard let worldspaces = world?.mapMarkerWorldspaces, !worldspaces.isEmpty else { return }
        inspection.worldspace = Self.step(
            inspection.worldspace,
            by: offset,
            count: worldspaces.count
        )
        inspection.marker = 0
    }

    public func inspectMarker(offset: Int) {
        let count = inspectedSites().count
        guard count > 0 else { return }
        inspection.marker = Self.step(inspection.marker, by: offset, count: count)
    }

    public func apply(_ action: MapMarkerAction) {
        let sites = inspectedSites()
        guard let world, sites.indices.contains(inspection.marker) else { return }
        let site = sites[inspection.marker]
        world.storeMarkerState(action.state, for: site.key)
        lastResultText = "\(site.name): \(action.rawValue)"
    }

    /// "Name (worldspace): state", or nil without markers.
    public var inspectedMarkerLine: String? {
        let sites = inspectedSites()
        guard
            let worldspace = inspectedWorldspace,
            sites.indices.contains(inspection.marker)
        else { return nil }
        let site = sites[inspection.marker]
        let state = site.state
        let words = [
            state.isVisible ? "shown" : "hidden",
            state.isDiscovered ? "discovered" : "undiscovered",
            state.canTravelTo ? "travel" : "no travel"
        ]
        return "\(site.name) (\(worldspace.name), \(inspection.marker + 1) of \(sites.count)): "
            + words.joined(separator: ", ")
    }

    var inspectedWorldspace: MapWorldspaceChoice? {
        let worldspaces = world?.mapMarkerWorldspaces ?? []
        return worldspaces.indices.contains(inspection.worldspace)
            ? worldspaces[inspection.worldspace] : nil
    }

    private func inspectedSites() -> [MapMarkerSite] {
        guard let worldspace = inspectedWorldspace else { return [] }
        return world?.mapMarkerSites(in: worldspace.formID) ?? []
    }

    private static func step(_ index: Int, by offset: Int, count: Int) -> Int {
        ((index + offset) % count + count) % count
    }
}

/// Which worldspace and marker the inspector points at.
nonisolated struct MapMarkerInspection: Equatable, Sendable {
    var worldspace = 0
    var marker = 0
}
