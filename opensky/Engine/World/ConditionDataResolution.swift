// Immutable M18 record-data snapshot for condition functions (issue #455).
//
// The evaluator can run off the main actor, so condition bodies never load
// plugins or reach into a live streamer. A caller builds this value from the
// three load-order stores and the reference-location facts it owns, then every
// function reads the same snapshot.

import Foundation

nonisolated struct ConditionDataResolution: @unchecked Sendable {
    let keywords: KeywordStore?
    let formLists: FormListStore?
    let locations: LocationStore?
    let sourcePlugin: String?

    private let currentLocations: [ReferenceKey: ResolvedFormID]
    private let editorLocations: [ReferenceKey: ResolvedFormID]

    static let empty = ConditionDataResolution()

    init(
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

    func currentLocation(of reference: ReferenceKey) -> ResolvedFormID? {
        currentLocations[reference]
    }

    func editorLocation(of reference: ReferenceKey) -> ResolvedFormID? {
        editorLocations[reference]
    }
}
