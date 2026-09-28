// Immutable M18 record-data snapshot for condition functions (issue #455).
//
// The evaluator can run off the main actor, so condition bodies never load
// plugins or reach into a live streamer. A caller builds this value from the
// three load-order stores and the reference-location facts it owns, then every
// function reads the same snapshot.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated public struct ConditionDataResolution: @unchecked Sendable, Sendable {
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
}
