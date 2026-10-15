// Record-data snapshot for condition functions. The evaluator can run off the
// main actor, so a condition body never loads plugins or reads a live streamer.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated public struct ConditionDataResolution: Sendable {
    public let keywords: KeywordStore?
    public let formLists: FormListStore?
    public let locations: LocationStore?
    public let sourcePlugin: String?

    private let currentLocations: [ReferenceKey: ResolvedFormID]
    private let editorLocations: [ReferenceKey: ResolvedFormID]
    private let interiors: [ReferenceKey: Bool]
    private let cells: [ReferenceKey: ReferenceCell]

    public static let empty = ConditionDataResolution()

    public init(
        keywords: KeywordStore? = nil,
        formLists: FormListStore? = nil,
        locations: LocationStore? = nil,
        sourcePlugin: String? = nil,
        currentLocations: [ReferenceKey: ResolvedFormID] = [:],
        editorLocations: [ReferenceKey: ResolvedFormID] = [:],
        interiors: [ReferenceKey: Bool] = [:],
        cells: [ReferenceKey: ReferenceCell] = [:]
    ) {
        self.keywords = keywords
        self.formLists = formLists
        self.locations = locations
        self.sourcePlugin = sourcePlugin
        self.currentLocations = currentLocations
        self.editorLocations = editorLocations
        self.interiors = interiors
        self.cells = cells
    }

    public func currentLocation(of reference: ReferenceKey) -> ResolvedFormID? {
        currentLocations[reference]
    }

    public func editorLocation(of reference: ReferenceKey) -> ResolvedFormID? {
        editorLocations[reference]
    }

    /// Whether the cell that holds `reference` is an interior; nil when it is not loaded.
    public func isInInterior(_ reference: ReferenceKey) -> Bool? {
        interiors[reference]
    }

    /// The loaded cell that holds `reference`; nil when it is not loaded.
    public func cell(of reference: ReferenceKey) -> ReferenceCell? {
        cells[reference]
    }

    /// A copy that reads FormIDs from `plugin`.
    public func with(sourcePlugin plugin: String?) -> Self {
        Self(
            keywords: keywords, formLists: formLists, locations: locations,
            sourcePlugin: plugin, currentLocations: currentLocations,
            editorLocations: editorLocations, interiors: interiors, cells: cells
        )
    }

    /// A copy that reads FormIDs from `plugin` and puts `reference` in `location`,
    /// for a check about a place the reference is going to.
    public func with(
        sourcePlugin plugin: String?,
        location: ResolvedFormID?,
        of reference: ReferenceKey
    ) -> Self {
        var current = currentLocations
        current[reference] = location
        return Self(
            keywords: keywords, formLists: formLists, locations: locations,
            sourcePlugin: plugin, currentLocations: current, editorLocations: editorLocations,
            interiors: interiors, cells: cells
        )
    }
}

/// The cell a reference stands in, in the load-order FormID space.
nonisolated public struct ReferenceCell: Equatable, Sendable {
    public let cell: FormID
    /// Nil for an interior cell.
    public let worldspace: FormID?

    public init(cell: FormID, worldspace: FormID?) {
        self.cell = cell
        self.worldspace = worldspace
    }
}
