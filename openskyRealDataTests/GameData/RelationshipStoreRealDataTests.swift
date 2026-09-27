// Env-gated RELA and ASTP decode and relationship-store acceptance over the
// user's own read-only load order (issue #502).
//
// Four questions, in the order milestone M21 needs them answered: does every
// RELA and ASTP record in the load order decode, does every association-type
// link find a decoded ASTP, does the pair query answer in both argument orders
// for a real authored pair, and does any record read a field OpenSky does not.
//
// Counts, editor IDs and tallies only — no game bytes leave the run
// (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky
import Testing

struct RelationshipStoreRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    @Test(.enabled(if: Self.dataRoot != nil))
    func decodesEveryRelationshipAndResolvesEveryAssociationType() throws {
        let root = try #require(Self.dataRoot)
        let plugins = ActivePluginFiles.load(root: root)
        let index = RecordIndex(
            plugins: plugins,
            recordTypes: RecordIndex.referenceRecordTypes
        )
        let store = RelationshipStore(index: index)

        print(
            "[INFO] RELA collected \(index.collectedCount(of: "RELA")), "
                + "winning \(index.count(of: "RELA")), "
                + "decoded \(store.relationships.count); "
                + "ASTP collected \(index.collectedCount(of: "ASTP")), "
                + "winning \(index.count(of: "ASTP")), "
                + "decoded \(store.associationTypes.count)"
        )
        // The five masters author 673 RELA and 20 ASTP; a load order that
        // carries more is a mod adding some, never one losing any.
        #expect(index.collectedCount(of: "RELA") >= 673)
        #expect(index.collectedCount(of: "ASTP") >= 20)
        #expect(store.relationships.count == index.count(of: "RELA"))
        #expect(store.associationTypes.count == index.count(of: "ASTP"))

        reportTallies(store)
        reportRanks(store)
        try checkAssociationTypeLinks(store)
        try checkPairQueries(store)
        try checkPinnedRecords(store)
    }

    /// A tally means a record carried a field this decoder does not read, or
    /// one it could not read. Both sources describe RELA and ASTP completely,
    /// so anything nonzero is a finding rather than an expected remainder.
    private func reportTallies(_ store: RelationshipStore) {
        var unknown: [FourCC: Int] = [:]
        var malformed: [FourCC: Int] = [:]
        var noData = 0
        for resolved in store.sortedRelationships {
            if resolved.relationship.data == nil {
                noData += 1
            }
            merge(resolved.relationship.skipped, into: &unknown, and: &malformed)
        }
        for resolved in store.sortedAssociationTypes {
            merge(resolved.associationType.skipped, into: &unknown, and: &malformed)
        }
        print(
            "[INFO] RELA/ASTP unknown fields \(describe(unknown)), "
                + "malformed fields \(describe(malformed)), "
                + "records without DATA \(noData), "
                + "duplicate pairs \(store.duplicatePairCount)"
        )
        #expect(unknown.isEmpty)
        #expect(malformed.isEmpty)
        #expect(noData == 0)
    }

    /// The rank histogram, the secret count under both readings of the flag,
    /// and the unknown byte at DATA offset 12. A nonzero unknown byte or a
    /// disagreement between the two secret flags is the observation that would
    /// settle which reading the game uses (`Relationship.secretHeaderFlag`).
    private func reportRanks(_ store: RelationshipStore) {
        var histogram: [String: Int] = [:]
        var dataSecret = 0
        var headerSecret = 0
        var nonzeroUnknownByte = 0
        var unnamedFlagBits: UInt8 = 0
        for resolved in store.sortedRelationships {
            guard let data = resolved.relationship.data else { continue }
            histogram["\(data.rank)", default: 0] += 1
            if data.flags.contains(.secret) {
                dataSecret += 1
            }
            if resolved.relationship.headerSecret {
                headerSecret += 1
            }
            if data.unknown != 0 {
                nonzeroUnknownByte += 1
            }
            unnamedFlagBits |= data.flags.rawValue & ~RelationshipFlags.secret.rawValue
        }
        let disagreeing = store.sortedRelationships
            .filter { $0.isSecret != $0.relationship.headerSecret }
            .map { $0.editorID ?? $0.id.description }
        print("[INFO] RELA records where the two secret flags disagree \(disagreeing)")
        print(
            "[INFO] RELA ranks \(histogram.sorted { $0.key < $1.key }), "
                + "DATA secret \(dataSecret), header secret \(headerSecret), "
                + "nonzero unknown byte \(nonzeroUnknownByte), "
                + String(format: "unnamed flag bits 0x%02X", unnamedFlagBits)
        )
        #expect(histogram.keys.allSatisfy { !$0.hasPrefix("unknown") })
    }

    /// Every ASTP link a relationship names has to reach a decoded record: the
    /// dialogue condition `HasAssociationType` (issue #508) reads exactly this
    /// link, and a dangling one would silently answer false.
    private func checkAssociationTypeLinks(_ store: RelationshipStore) throws {
        var linked = 0
        var unresolved: [String] = []
        for resolved in store.sortedRelationships {
            guard resolved.rawAssociationType != nil else { continue }
            linked += 1
            if resolved.associationType == nil {
                unresolved.append(resolved.editorID ?? resolved.id.description)
            }
        }
        let used = Set(store.sortedRelationships.compactMap(\.associationType?.id))
        print(
            "[INFO] RELA association-type links \(linked), "
                + "unresolved \(unresolved.count) \(unresolved.sorted()), "
                + "distinct ASTP referenced \(used.count) of \(store.associationTypes.count), "
                + "family associations "
                + "\(store.sortedAssociationTypes.count(where: \.isFamilyAssociation))"
        )
        print(
            "[INFO] ASTP editor IDs "
                + "\(store.sortedAssociationTypes.map { $0.editorID ?? "-" }.sorted())"
        )
        #expect(unresolved.isEmpty)
        #expect(linked > 0)
    }

    /// The pair query, checked against records the load order actually
    /// authored rather than against pinned FormIDs: every relationship that
    /// names both sides has to be findable from either side, and the record it
    /// returns has to keep the authored direction.
    private func checkPairQueries(_ store: RelationshipStore) throws {
        var paired = 0
        var reachableFromBothSides = 0
        for resolved in store.sortedRelationships {
            guard let parent = resolved.parent, let child = resolved.child else { continue }
            paired += 1
            let forward = store.relationship(between: parent, and: child)
            let backward = store.relationship(between: child, and: parent)
            if forward == backward, forward != nil {
                reachableFromBothSides += 1
            }
        }
        print(
            "[INFO] RELA pairs naming both sides \(paired), "
                + "reachable from either side \(reachableFromBothSides)"
        )
        // Every pair is reachable from both sides; the only pairs that can go
        // missing from the index are the ones a duplicate overwrote.
        #expect(reachableFromBothSides == paired - store.duplicatePairCount)

        let sample = try #require(store.sortedRelationships.first {
            $0.parent != nil && $0.child != nil && $0.associationType != nil
        })
        let parent = try #require(sample.parent)
        let child = try #require(sample.child)
        print(
            "[INFO] sample \(sample.editorID ?? sample.id.description): "
                + "rank \(sample.rank?.description ?? "-"), "
                + "association \(sample.associationType?.editorID ?? "-"), "
                + "parent title \(sample.title(ofParent: true, female: false) ?? "-"), "
                + "child title \(sample.title(ofParent: false, female: true) ?? "-")"
        )
        #expect(store.relationship(between: child, and: parent)?.id == sample.id)
        #expect(store.relationships(involving: parent).contains { $0.id == sample.id })
        #expect(store.relationships(involving: child).contains { $0.id == sample.id })
    }

    /// Two association types and one relationship the vanilla masters author,
    /// pinned by editor ID so a patch that moves a record does not fail the
    /// suite for the wrong reason. `AlvorSigrid` is the Riverwood smith and his
    /// wife: a lover-ranked pair carrying the `Spouse` association.
    private func checkPinnedRecords(_ store: RelationshipStore) throws {
        let spouse = try #require(store.associationType(editorID: "Spouse"))
        #expect(spouse.isFamilyAssociation)
        #expect(spouse.associationType.maleParentTitle == "Husband")
        #expect(spouse.associationType.femaleParentTitle == "Wife")
        #expect(spouse.associationType.maleChildTitle == "Husband")
        #expect(spouse.associationType.femaleChildTitle == "Wife")

        let parentChild = try #require(store.associationType(editorID: "ParentChild"))
        #expect(parentChild.isFamilyAssociation)
        #expect(parentChild.associationType.parentTitle(female: false) == "Father")
        #expect(parentChild.associationType.parentTitle(female: true) == "Mother")
        #expect(parentChild.associationType.childTitle(female: false) == "Son")
        #expect(parentChild.associationType.childTitle(female: true) == "Daughter")

        // Courting names only the parent side, which is what makes the
        // gendered fallback on `childTitle` a real case rather than a guard.
        let courting = try #require(store.associationType(editorID: "Courting"))
        #expect(!courting.isFamilyAssociation)
        #expect(courting.associationType.parentTitle(female: true) == "Girlfriend")
        #expect(courting.associationType.childTitle(female: true) == nil)

        let marriage = try #require(store.relationship(editorID: "AlvorSigrid"))
        let parent = try #require(marriage.parent)
        let child = try #require(marriage.child)
        #expect(marriage.rank == .lover)
        #expect(marriage.rank?.signedRank == 4)
        #expect(marriage.associationType?.id == spouse.id)
        #expect(marriage.title(ofParent: true, female: false) == "Husband")
        #expect(marriage.title(ofParent: false, female: true) == "Wife")
        #expect(store.relationship(between: parent, and: child)?.id == marriage.id)
        #expect(store.relationship(between: child, and: parent)?.id == marriage.id)

        let spouses = store.sortedRelationships.count { $0.associationType?.id == spouse.id }
        print("[INFO] Spouse-associated relationships \(spouses)")
        #expect(spouses >= 59)
    }

    private func merge(
        _ tally: ReferenceRecordTally,
        into unknown: inout [FourCC: Int],
        and malformed: inout [FourCC: Int]
    ) {
        for (kind, count) in tally.counts {
            switch kind {
            case let .unknownField(type): unknown[type, default: 0] += count
            case let .malformedField(type): malformed[type, default: 0] += count
            case .unknownDefaultObjectTag: continue
            }
        }
    }

    private func describe(_ counts: [FourCC: Int]) -> String {
        counts.isEmpty
            ? "none"
            : counts.sorted { $0.key.description < $1.key.description }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: " ")
    }
}
