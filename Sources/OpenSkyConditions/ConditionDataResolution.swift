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

    public static let empty = ConditionDataResolution()

    public init(
        keywords: KeywordStore? = nil,
        formLists: FormListStore? = nil,
        locations: LocationStore? = nil,
        sourcePlugin: String? = nil,
        currentLocations: [ReferenceKey: ResolvedFormID] = [:],
        editorLocations: [ReferenceKey: ResolvedFormID] = [:]
    ) {
        self.keywords = keywords
        self.formLists = formLists
        self.locations = locations
        self.sourcePlugin = sourcePlugin
        self.currentLocations = currentLocations
        self.editorLocations = editorLocations
    }

    public func currentLocation(of reference: ReferenceKey) -> ResolvedFormID? {
        currentLocations[reference]
    }

    public func editorLocation(of reference: ReferenceKey) -> ResolvedFormID? {
        editorLocations[reference]
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
            sourcePlugin: plugin, currentLocations: current, editorLocations: editorLocations
        )
    }
}
