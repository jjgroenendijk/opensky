// Load-order-wide RELA and ASTP lookup above RecordIndex, like `FactionStore`:
// the winning record per identity, editor-ID lookup, the two actor bases
// resolved, and the ASTP titles joined. `relationship(between:and:)` answers in
// either argument order; `parent` and `child` keep the authored direction.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public struct ResolvedAssociationType: Equatable, Sendable {
    public let id: ResolvedFormID
    public let associationType: AssociationType

    public var editorID: String? {
        associationType.editorID
    }

    public var isFamilyAssociation: Bool {
        associationType.isFamilyAssociation
    }
}

nonisolated public struct ResolvedRelationship: Equatable, Sendable {
    public let id: ResolvedFormID
    public let relationship: Relationship
    public let sourcePlugin: String
    /// The two NPC_ bases after resolution. Nil when the record leaves the link
    /// null; the store keeps such a record for identity lookup but it never
    /// enters the pair index, because it names no pair.
    public let parent: ResolvedFormID?
    public let child: ResolvedFormID?
    /// The ASTP the record names, joined when the load order carries it. Nil
    /// covers both "no link authored" and "link dangles" — `rawAssociationType`
    /// separates them.
    public let associationType: ResolvedAssociationType?

    public var editorID: String? {
        relationship.editorID
    }

    public var rawAssociationType: FormID? {
        relationship.associationType
    }

    public var rank: RelationshipRank? {
        relationship.rank
    }

    public var isSecret: Bool {
        relationship.isSecret
    }

    /// The title the named side carries, or nil when no association type
    /// resolved or it authored no title for that side.
    public func title(ofParent isParent: Bool, female: Bool) -> String? {
        guard let associationType = associationType?.associationType else { return nil }
        return isParent
            ? associationType.parentTitle(female: female)
            : associationType.childTitle(female: female)
    }
}

nonisolated public struct RelationshipStore: Sendable {
    private let index: RecordIndex
    private let relationshipTable: ResolvedRecordTable<ResolvedRelationship>
    private let associationTypeTable: ResolvedRecordTable<ResolvedAssociationType>
    /// How many pairs were named by more than one record. Vanilla authors each
    /// pair once; the load-order winner is the one kept.
    public private(set) var duplicatePairCount = 0
    private var byPair: [String: ResolvedRelationship] = [:]
    private var byActor: [ReferenceKey: [ResolvedRelationship]] = [:]

    public var relationships: [ResolvedFormID: ResolvedRelationship] {
        relationshipTable.values
    }

    public var associationTypes: [ResolvedFormID: ResolvedAssociationType] {
        associationTypeTable.values
    }

    public var skippedRecords: SkippedRecords {
        relationshipTable.skipped.merging(associationTypeTable.skipped)
    }

    /// Every relationship the load order carries, ordered by identity so a
    /// caller that prints or counts them gets the same answer on every run.
    public var sortedRelationships: [ResolvedRelationship] {
        relationships.values.sorted { Self.precedes($0.id, $1.id) }
    }

    public var sortedAssociationTypes: [ResolvedAssociationType] {
        associationTypes.values.sorted { Self.precedes($0.id, $1.id) }
    }

    public init(index: RecordIndex) {
        self.index = index
        // ASTP first: a relationship joins its association type as it is built.
        let types = ResolvedRecordTable(
            index: index,
            types: ["ASTP"],
            decode: { try AssociationType(record: $0.record) },
            editorID: \.editorID,
            resolve: { id, type, _ in ResolvedAssociationType(id: id, associationType: type) }
        )
        associationTypeTable = types
        relationshipTable = ResolvedRecordTable(
            index: index,
            types: ["RELA"],
            decode: { try Relationship(record: $0.record) },
            editorID: \.editorID,
            resolve: { id, relationship, sourcePlugin in
                ResolvedRelationship(
                    id: id,
                    relationship: relationship,
                    sourcePlugin: sourcePlugin,
                    parent: index.resolvedID(relationship.parent, fromPlugin: sourcePlugin),
                    child: index.resolvedID(relationship.child, fromPlugin: sourcePlugin),
                    associationType: index.resolvedID(
                        relationship.associationType,
                        fromPlugin: sourcePlugin
                    ).flatMap { types.value($0) }
                )
            }
        )
        for resolved in relationshipTable.orderedValues {
            addToPairIndexes(resolved, parent: resolved.parent, child: resolved.child)
        }
    }

    public init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(plugins: plugins, recordTypes: ["RELA", "ASTP"]))
    }

    public func relationship(_ id: ResolvedFormID) -> ResolvedRelationship? {
        relationshipTable.value(id)
    }

    public func relationship(editorID: String) -> ResolvedRelationship? {
        relationshipTable.value(editorID: editorID)
    }

    public func associationType(editorID: String) -> ResolvedAssociationType? {
        associationTypeTable.value(editorID: editorID)
    }

    /// The relationship between two actor bases, in either argument order. The
    /// returned record keeps the authored direction in `parent` and `child`.
    public func relationship(
        between left: ResolvedFormID,
        and right: ResolvedFormID
    ) -> ResolvedRelationship? {
        byPair[Self.pairKey(left, right)]
    }

    /// The rank the pair holds, in either argument order. Nil when no record
    /// names the pair — which is not the same as `.acquaintance`, the rank a
    /// record can author to mean deliberate indifference.
    public func rank(
        between left: ResolvedFormID,
        and right: ResolvedFormID
    ) -> RelationshipRank? {
        relationship(between: left, and: right)?.rank
    }

    /// Every relationship one actor base takes part in, on either side,
    /// ordered by identity.
    public func relationships(involving actor: ResolvedFormID) -> [ResolvedRelationship] {
        byActor[ReferenceKey(resolved: actor)] ?? []
    }

    public func resolvedID(_ id: FormID, fromPlugin pluginName: String) -> ResolvedFormID? {
        index.resolvedID(id, fromPlugin: pluginName)
    }

    public func resolve(_ id: FormID, fromPlugin pluginName: String) -> ResolvedRelationship? {
        guard let resolved = resolvedID(id, fromPlugin: pluginName) else { return nil }
        return relationship(resolved)
    }

    /// A relationship link as text: its editor ID when the load order carries
    /// the record, and an explicit unresolved marker when it does not.
    public func displayString(for id: FormID, fromPlugin pluginName: String) -> String {
        guard let resolved = resolve(id, fromPlugin: pluginName) else {
            return "[UNRESOLVED] \(id)"
        }
        return resolved.editorID ?? resolved.id.description
    }

    /// Adds one decoded relationship to the pair and per-actor indexes. A
    /// record that names only one side still lists under that side, because a
    /// caller asking what an actor takes part in wants to see it.
    private mutating func addToPairIndexes(
        _ resolved: ResolvedRelationship,
        parent: ResolvedFormID?,
        child: ResolvedFormID?
    ) {
        for actor in [parent, child].compactMap(\.self) {
            let key = ReferenceKey(resolved: actor)
            byActor[key, default: []].append(resolved)
            byActor[key]?.sort { Self.precedes($0.id, $1.id) }
        }
        guard let parent, let child else { return }
        let key = Self.pairKey(parent, child)
        if byPair[key] != nil {
            duplicatePairCount += 1
        }
        byPair[key] = resolved
    }

    private static func precedes(_ left: ResolvedFormID, _ right: ResolvedFormID) -> Bool {
        left.plugin.caseInsensitiveCompare(right.plugin) == .orderedSame
            ? left.objectID < right.objectID
            : left.plugin.localizedCaseInsensitiveCompare(right.plugin) == .orderedAscending
    }

    /// Unordered pair key: both identities lowercased and sorted, so a lookup
    /// finds the record whichever actor comes first and however the plugin is cased.
    private static func pairKey(_ left: ResolvedFormID, _ right: ResolvedFormID) -> String {
        [left, right]
            .map { "\($0.plugin.lowercased()):\($0.objectID)" }
            .sorted()
            .joined(separator: "|")
    }
}

nonisolated public enum RelationshipStoreLoader: Sendable {
    public static func load(root: GameDataRoot, baseFile: ESMFile? = nil) -> RelationshipStore {
        RelationshipStore(plugins: ActivePluginFiles.load(root: root, baseFile: baseFile))
    }
}
