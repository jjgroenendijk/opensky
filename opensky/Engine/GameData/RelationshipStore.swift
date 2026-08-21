// Load-order-wide RELA and ASTP lookup above RecordIndex, in the FactionStore
// shape: the winning record per identity, lookup by identity and by editor ID,
// and the joins a consumer would otherwise redo — a relationship's two actor
// bases resolved, and its ASTP link joined to the titles it names.
//
// The query the rest of milestone M21 needs is the pair one: "what are these
// two actors to each other", asked without knowing which of them the record
// calls the parent. `relationship(between:and:)` answers it in either argument
// order and hands back the record, whose `parent` and `child` keep the
// authored direction for a caller that needs it (a child title only makes
// sense on the child side).
//
// Nothing here decides hostility or evaluates a condition. Those read this
// store and are issues #503 and #508.

import Foundation

nonisolated struct ResolvedAssociationType: Equatable {
    let id: ResolvedFormID
    let associationType: AssociationType
    let sourcePlugin: String

    var editorID: String? {
        associationType.editorID
    }

    var isFamilyAssociation: Bool {
        associationType.isFamilyAssociation
    }
}

nonisolated struct ResolvedRelationship: Equatable {
    let id: ResolvedFormID
    let relationship: Relationship
    let sourcePlugin: String
    /// The two NPC_ bases after resolution. Nil when the record leaves the link
    /// null; the store keeps such a record for identity lookup but it never
    /// enters the pair index, because it names no pair.
    let parent: ResolvedFormID?
    let child: ResolvedFormID?
    /// The ASTP the record names, joined when the load order carries it. Nil
    /// covers both "no link authored" and "link dangles" — `rawAssociationType`
    /// separates them.
    let associationType: ResolvedAssociationType?

    var editorID: String? {
        relationship.editorID
    }

    var rawAssociationType: FormID? {
        relationship.associationType
    }

    var rank: RelationshipRank? {
        relationship.rank
    }

    var isSecret: Bool {
        relationship.isSecret
    }

    /// The title the named side carries, or nil when no association type
    /// resolved or it authored no title for that side.
    func title(ofParent isParent: Bool, female: Bool) -> String? {
        guard let associationType = associationType?.associationType else { return nil }
        return isParent
            ? associationType.parentTitle(female: female)
            : associationType.childTitle(female: female)
    }
}

/// Unordered key for the pair index. Both actor identities are normalized to a
/// lowercased plugin name and then sorted, so a lookup finds the record no
/// matter which actor the caller passes first or how the plugin name is cased.
nonisolated struct RelationshipPairKey: Hashable {
    private let first: String
    private let second: String

    init(_ left: ResolvedFormID, _ right: ResolvedFormID) {
        let leftKey = Self.text(left)
        let rightKey = Self.text(right)
        if leftKey <= rightKey {
            first = leftKey
            second = rightKey
        } else {
            first = rightKey
            second = leftKey
        }
    }

    private static func text(_ id: ResolvedFormID) -> String {
        "\(id.plugin.lowercased()):\(id.objectID)"
    }
}

nonisolated struct RelationshipStore {
    private let index: RecordIndex
    private(set) var relationships: [ResolvedFormID: ResolvedRelationship] = [:]
    private(set) var associationTypes: [ResolvedFormID: ResolvedAssociationType] = [:]
    /// How many pairs were named by more than one record. Vanilla authors each
    /// pair once; a load order that does not is a fact worth reporting rather
    /// than a fault, and the load-order winner is the one kept.
    private(set) var duplicatePairCount = 0
    private var relationshipsByEditorID: [String: ResolvedRelationship] = [:]
    private var associationTypesByEditorID: [String: ResolvedAssociationType] = [:]
    private var byPair: [RelationshipPairKey: ResolvedRelationship] = [:]
    private var byActor: [ResolvedFormID: [ResolvedRelationship]] = [:]

    /// Every relationship the load order carries, ordered by identity so a
    /// caller that prints or counts them gets the same answer on every run.
    var sortedRelationships: [ResolvedRelationship] {
        relationships.values.sorted { Self.precedes($0.id, $1.id) }
    }

    var sortedAssociationTypes: [ResolvedAssociationType] {
        associationTypes.values.sorted { Self.precedes($0.id, $1.id) }
    }

    init(index: RecordIndex) {
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

    init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(plugins: plugins, recordTypes: ["RELA", "ASTP"]))
    }

    func relationship(_ id: ResolvedFormID) -> ResolvedRelationship? {
        relationships[canonicalMatch(id, in: relationships)]
    }

    func relationship(editorID: String) -> ResolvedRelationship? {
        relationshipsByEditorID[editorID.lowercased()]
    }

    func associationType(_ id: ResolvedFormID) -> ResolvedAssociationType? {
        associationTypes[canonicalMatch(id, in: associationTypes)]
    }

    func associationType(editorID: String) -> ResolvedAssociationType? {
        associationTypesByEditorID[editorID.lowercased()]
    }

    /// The relationship between two actor bases, in either argument order. The
    /// returned record keeps the authored direction in `parent` and `child`.
    func relationship(
        between left: ResolvedFormID,
        and right: ResolvedFormID
    ) -> ResolvedRelationship? {
        byPair[RelationshipPairKey(left, right)]
    }

    /// The rank the pair holds, in either argument order. Nil when no record
    /// names the pair — which is not the same as `.acquaintance`, the rank a
    /// record can author to mean deliberate indifference.
    func rank(
        between left: ResolvedFormID,
        and right: ResolvedFormID
    ) -> RelationshipRank? {
        relationship(between: left, and: right)?.rank
    }

    /// Every relationship one actor base takes part in, on either side,
    /// ordered by identity.
    func relationships(involving actor: ResolvedFormID) -> [ResolvedRelationship] {
        byActor[canonicalMatch(actor, in: byActor)] ?? []
    }

    func resolvedID(_ id: FormID, fromPlugin pluginName: String) -> ResolvedFormID? {
        guard case let .resolved(resolved) = index.resolve(id, fromPlugin: pluginName) else {
            return nil
        }
        return resolved
    }

    func resolve(_ id: FormID, fromPlugin pluginName: String) -> ResolvedRelationship? {
        guard let resolved = resolvedID(id, fromPlugin: pluginName) else { return nil }
        return relationship(resolved)
    }

    /// A relationship link as text: its editor ID when the load order carries
    /// the record, and an explicit unresolved marker when it does not.
    func displayString(for id: FormID, fromPlugin pluginName: String) -> String {
        guard let resolved = resolve(id, fromPlugin: pluginName) else {
            return "[UNRESOLVED] \(id)"
        }
        return resolved.editorID ?? resolved.id.description
    }

    private mutating func addAssociationType(_ id: ResolvedFormID) {
        guard
            case let .decoded(type, sourcePlugin) = index.decode(
                id,
                using: AssociationType.init(record:)
            )
        else { return }
        let resolved = ResolvedAssociationType(
            id: id,
            associationType: type,
            sourcePlugin: sourcePlugin
        )
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
        let key = RelationshipPairKey(parent, child)
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
}

nonisolated enum RelationshipStoreLoader {
    static func load(root: GameDataRoot, baseFile: ESMFile? = nil) -> RelationshipStore {
        RelationshipStore(plugins: ActivePluginFiles.load(root: root, baseFile: baseFile))
    }
}
