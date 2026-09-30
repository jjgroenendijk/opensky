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
    public private(set) var relationships: [ResolvedFormID: ResolvedRelationship] = [:]
    public private(set) var associationTypes: [ResolvedFormID: ResolvedAssociationType] = [:]
    /// How many pairs were named by more than one record. Vanilla authors each
    /// pair once; a load order that does not is a fact worth reporting rather
    /// than a fault, and the load-order winner is the one kept.
    public private(set) var duplicatePairCount = 0
    private var relationshipsByEditorID: [String: ResolvedRelationship] = [:]
    private var associationTypesByEditorID: [String: ResolvedAssociationType] = [:]
    private var byPair: [String: ResolvedRelationship] = [:]
    private var byActor: [ResolvedFormID: [ResolvedRelationship]] = [:]

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
        let orderedIDs = index.records.keys.sorted {
            RecordStoreOrdering.precedes($0, $1, index: index)
        }
        // ASTP first: a relationship joins its association type when it is
        // added, so the types have to be in place before the RELA pass.
        for id in orderedIDs where index.records[id]?.record.type == "ASTP" {
            addAssociationType(id)
        }
        for id in orderedIDs where index.records[id]?.record.type == "RELA" {
            addRelationship(id)
        }
    }

    public init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(plugins: plugins, recordTypes: ["RELA", "ASTP"]))
    }

    public func relationship(_ id: ResolvedFormID) -> ResolvedRelationship? {
        relationships[canonicalMatch(id, in: relationships)]
    }

    public func relationship(editorID: String) -> ResolvedRelationship? {
        relationshipsByEditorID[editorID.lowercased()]
    }

    public func associationType(_ id: ResolvedFormID) -> ResolvedAssociationType? {
        associationTypes[canonicalMatch(id, in: associationTypes)]
    }

    public func associationType(editorID: String) -> ResolvedAssociationType? {
        associationTypesByEditorID[editorID.lowercased()]
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
        byActor[canonicalMatch(actor, in: byActor)] ?? []
    }

    public func resolvedID(_ id: FormID, fromPlugin pluginName: String) -> ResolvedFormID? {
        guard case let .resolved(resolved) = index.resolve(id, fromPlugin: pluginName) else {
            return nil
        }
        return resolved
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

    private mutating func addAssociationType(_ id: ResolvedFormID) {
        guard
            case let .decoded(type, _) = index.decode(
                id,
                using: AssociationType.init(record:)
            )
        else { return }
        let resolved = ResolvedAssociationType(id: id, associationType: type)
        associationTypes[id] = resolved
        if let editorID = type.editorID {
            associationTypesByEditorID[editorID.lowercased()] = resolved
        }
    }

    private mutating func addRelationship(_ id: ResolvedFormID) {
        guard
            case let .decoded(relationship, sourcePlugin) = index.decode(
                id,
                using: Relationship.init(record:)
            )
        else { return }
        let parent = resolvedID(relationship.parent, fromPlugin: sourcePlugin)
        let child = resolvedID(relationship.child, fromPlugin: sourcePlugin)
        let resolved = ResolvedRelationship(
            id: id,
            relationship: relationship,
            sourcePlugin: sourcePlugin,
            parent: parent,
            child: child,
            associationType: resolvedID(
                relationship.associationType,
                fromPlugin: sourcePlugin
            ).flatMap { associationType($0) }
        )
        relationships[id] = resolved
        if let editorID = relationship.editorID {
            relationshipsByEditorID[editorID.lowercased()] = resolved
        }
        addToPairIndexes(resolved, parent: parent, child: child)
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
            let key = canonicalMatch(actor, in: byActor)
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

    private func resolvedID(_ id: FormID?, fromPlugin pluginName: String) -> ResolvedFormID? {
        guard let id else { return nil }
        return resolvedID(id, fromPlugin: pluginName)
    }

    /// Identity is plugin-plus-object-id compared case-insensitively, matching
    /// how the other stores match a key built from a differently cased plugin
    /// name.
    private func canonicalMatch(
        _ id: ResolvedFormID,
        in values: [ResolvedFormID: some Any]
    ) -> ResolvedFormID {
        if values[id] != nil {
            return id
        }
        return values.keys.first {
            $0.objectID == id.objectID
                && $0.plugin.caseInsensitiveCompare(id.plugin) == .orderedSame
        } ?? id
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
