// Synthetic load-order, editor-id, pair-query and ASTP-join coverage for
// RelationshipStore. No game-derived bytes.

import Foundation
@testable import opensky
import Testing

struct RelationshipStoreTests {
    @Test
    func laterPluginWinsByIdentityAndEditorID() throws {
        let base = try RelationshipFixture.plugin(relationships: [
            RelationshipFixture.record(
                formID: 0x20,
                editorID: "OldName",
                body: RelationshipFixture.data(parent: 0x100, child: 0x101, rank: 7)
            )
        ])
        let patch = try RelationshipFixture.plugin(
            masters: ["Base.esm"],
            relationships: [
                RelationshipFixture.record(
                    formID: 0x20,
                    editorID: "NewName",
                    body: RelationshipFixture.data(parent: 0x100, child: 0x101, rank: 1)
                )
            ]
        )
        let store = RelationshipStore(plugins: [("Base.esm", base), ("Patch.esp", patch)])

        let resolved = try #require(store.relationship(id("Base.esm", 0x20)))
        #expect(resolved.editorID == "NewName")
        #expect(resolved.sourcePlugin == "Patch.esp")
        #expect(resolved.rank == .ally)
        #expect(store.relationship(editorID: "newname")?.id == resolved.id)
        #expect(store.relationship(editorID: "OldName") == nil)
        #expect(store.relationships.count == 1)
        #expect(store.duplicatePairCount == 0)
    }

    @Test
    func findsThePairInEitherArgumentOrderAndKeepsTheAuthoredDirection() throws {
        let store = try singlePluginStore()
        let parent = id("Base.esm", 0x100)
        let child = id("Base.esm", 0x101)

        let forward = try #require(store.relationship(between: parent, and: child))
        let backward = try #require(store.relationship(between: child, and: parent))
        #expect(forward == backward)
        #expect(forward.editorID == "RelaParentChild")
        // The query is unordered, the record is not.
        #expect(forward.parent == parent)
        #expect(forward.child == child)
        #expect(store.rank(between: child, and: parent) == .confidant)

        // A pair nobody authored is nil, not a default rank.
        #expect(store.relationship(between: parent, and: id("Base.esm", 0x999)) == nil)
        #expect(store.rank(between: parent, and: id("Base.esm", 0x999)) == nil)
    }

    @Test
    func matchesAPairKeyBuiltFromADifferentlyCasedPluginName() throws {
        let store = try singlePluginStore()

        #expect(store.relationship(
            between: id("BASE.ESM", 0x101),
            and: id("base.esm", 0x100)
        )?.editorID == "RelaParentChild")
        #expect(store.relationship(id("BASE.ESM", 0x20))?.editorID == "RelaParentChild")
        #expect(store.relationships(involving: id("BASE.ESM", 0x100)).count == 2)
    }

    @Test
    func joinsTheAssociationTypeAndItsTitles() throws {
        let store = try singlePluginStore()

        let joined = try #require(store.relationship(editorID: "RelaParentChild"))
        let type = try #require(joined.associationType)
        #expect(type.editorID == "AssocParentChild")
        #expect(type.isFamilyAssociation)
        #expect(joined.title(ofParent: true, female: true) == "Mother")
        #expect(joined.title(ofParent: false, female: false) == "Son")
        #expect(store.associationType(editorID: "assocparentchild")?.id == type.id)
        #expect(store.associationTypes.count == 1)

        // A link nothing in the load order carries stays visible as its raw
        // FormID rather than disappearing from the record.
        let dangling = try #require(store.relationship(editorID: "RelaDangling"))
        #expect(dangling.associationType == nil)
        #expect(dangling.rawAssociationType == FormID(0x999))
        #expect(dangling.title(ofParent: true, female: false) == nil)
    }

    @Test
    func listsEveryRelationshipAnActorTakesPartInOnEitherSide() throws {
        let store = try singlePluginStore()

        #expect(store.relationships(involving: id("Base.esm", 0x100)).map(\.editorID)
            == ["RelaParentChild", "RelaDangling"])
        #expect(store.relationships(involving: id("Base.esm", 0x102)).map(\.editorID)
            == ["RelaDangling"])
        #expect(store.relationships(involving: id("Base.esm", 0x999)).isEmpty)
        #expect(store.sortedRelationships.map(\.editorID)
            == ["RelaParentChild", "RelaDangling", "RelaHalfNamed"])
    }

    @Test
    func aRecordThatNamesOnlyOneSideStaysOutOfThePairIndex() throws {
        let store = try singlePluginStore()

        let halfNamed = try #require(store.relationship(editorID: "RelaHalfNamed"))
        #expect(halfNamed.parent == id("Base.esm", 0x103))
        #expect(halfNamed.child == nil)
        #expect(store.relationships(involving: id("Base.esm", 0x103)).map(\.editorID)
            == ["RelaHalfNamed"])
        #expect(store.relationship(between: id("Base.esm", 0x103), and: id("Base.esm", 0x100))
            == nil)
    }

    @Test
    func aSecondRecordForOnePairIsCountedAndTheLoadOrderWinnerIsKept() throws {
        let file = try RelationshipFixture.plugin(relationships: [
            RelationshipFixture.record(
                formID: 0x20,
                editorID: "RelaFirst",
                body: RelationshipFixture.data(parent: 0x100, child: 0x101, rank: 1)
            ),
            RelationshipFixture.record(
                formID: 0x21,
                editorID: "RelaSecond",
                body: RelationshipFixture.data(parent: 0x101, child: 0x100, rank: 8)
            )
        ])
        let store = RelationshipStore(plugins: [("Base.esm", file)])

        #expect(store.duplicatePairCount == 1)
        #expect(store.relationship(
            between: id("Base.esm", 0x100),
            and: id("Base.esm", 0x101)
        )?.editorID == "RelaSecond")
    }

    @Test
    func aRelationshipLinkPrintsItsEditorIDOrAnExplicitUnresolvedMarker() throws {
        let store = try singlePluginStore()

        #expect(store.displayString(for: FormID(0x20), fromPlugin: "Base.esm")
            == "RelaParentChild")
        #expect(store.displayString(for: FormID(0x999), fromPlugin: "Base.esm")
            == "[UNRESOLVED] 00000999")
        #expect(store.resolve(FormID(0x20), fromPlugin: "Base.esm")?.editorID
            == "RelaParentChild")
    }

    /// One plugin holding the four records every test above reads: a full
    /// parent/child pair with a family association, a pair whose ASTP link
    /// dangles, and a record that names only its parent.
    private func singlePluginStore() throws -> RelationshipStore {
        let file = try RelationshipFixture.plugin(
            relationships: [
                RelationshipFixture.record(
                    formID: 0x20,
                    editorID: "RelaParentChild",
                    body: RelationshipFixture.data(
                        parent: 0x100,
                        child: 0x101,
                        rank: 2,
                        associationType: 0x30
                    )
                ),
                RelationshipFixture.record(
                    formID: 0x21,
                    editorID: "RelaDangling",
                    body: RelationshipFixture.data(
                        parent: 0x100,
                        child: 0x102,
                        rank: 6,
                        associationType: 0x999
                    )
                ),
                RelationshipFixture.record(
                    formID: 0x22,
                    editorID: "RelaHalfNamed",
                    body: RelationshipFixture.data(parent: 0x103, child: 0, rank: 4)
                )
            ],
            associationTypes: [
                RelationshipFixture.associationType(
                    formID: 0x30,
                    editorID: "AssocParentChild",
                    maleParent: "Father",
                    femaleParent: "Mother",
                    maleChild: "Son",
                    femaleChild: "Daughter",
                    flags: 0x0000_0001
                )
            ]
        )
        return RelationshipStore(plugins: [("Base.esm", file)])
    }

    private func id(_ plugin: String, _ objectID: UInt32) -> ResolvedFormID {
        ResolvedFormID(plugin: plugin, objectID: objectID)
    }
}
