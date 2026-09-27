// RuntimeReferenceIndex unit tests over synthetic ESMFixture record bytes.
// No Metal device and no plugin tree: the index is pure value logic, so the
// records are decoded straight from fixture bytes.

import Foundation
@testable import opensky
import simd
import Testing

struct RuntimeReferenceIndexTests {
    // MARK: - Fixtures

    private func record(_ bytes: Data) throws -> ESMRecord {
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("fixture did not produce a record")
        }
        return record
    }

    private func placedReference(
        formID: UInt32,
        base: UInt32 = 0x100,
        position: SIMD3<Float> = .zero
    ) throws -> PlacedReference {
        var name = Data()
        name.appendUInt32(base)
        var data = Data()
        for value in [position.x, position.y, position.z, 0, 0, 0] {
            data.appendFloat32(value)
        }
        let fields = ESMFixture.field("NAME", name) + ESMFixture.field("DATA", data)
        return try PlacedReference(
            record: record(ESMFixture.record("REFR", formID: formID, data: fields))
        )
    }

    private func placedActor(formID: UInt32, base: UInt32 = 0x101) throws -> PlacedActor {
        var name = Data()
        name.appendUInt32(base)
        let fields = ESMFixture.field("NAME", name)
            + ESMFixture.field("DATA", Data(count: 24))
        return try PlacedActor(
            record: record(ESMFixture.record("ACHR", formID: formID, data: fields))
        )
    }

    private func entry(
        formID: UInt32,
        plugin: String = "skyrim.esm",
        isPersistent: Bool = false
    ) throws -> RuntimeReferenceEntry {
        let id = FormID(formID)
        return try RuntimeReferenceEntry(
            key: .plugin(name: plugin, objectID: id.objectID),
            formID: id,
            isPersistent: isPersistent,
            record: .reference(placedReference(formID: formID))
        )
    }

    // MARK: - Lookup

    @Test func emptyIndexAnswersNothing() {
        let index = RuntimeReferenceIndex.empty
        #expect(index.isEmpty)
        #expect(index.sortedEntries().isEmpty)
        #expect(index[.plugin(name: "skyrim.esm", objectID: 0x200)] == nil)
        #expect(index.entry(for: FormID(0x200)) == nil)
        #expect(index.sortedKeys().isEmpty)
    }

    @Test func findsEntryByKeyAndByRawFormID() throws {
        let index = try RuntimeReferenceIndex(entries: [
            entry(formID: 0x0000_0200), entry(formID: 0x0100_0201, isPersistent: true)
        ])
        #expect(index.count == 2)
        let byKey = try #require(index[.plugin(name: "skyrim.esm", objectID: 0x200)])
        #expect(byKey.formID == FormID(0x0000_0200))
        #expect(byKey.isPersistent == false)
        let byFormID = try #require(index.entry(for: FormID(0x0100_0201)))
        #expect(byFormID.key == .plugin(name: "skyrim.esm", objectID: 0x201))
        #expect(byFormID.isPersistent)
        // The raw FormID carries the load-order master index, so a same-object
        // ID under a different master index is a different raw lookup.
        #expect(index.entry(for: FormID(0x0000_0201)) == nil)
    }

    @Test func retainsBothReferenceAndActorRecords() throws {
        let reference = try placedReference(formID: 0x200, position: SIMD3(1, 2, 3))
        let actor = try placedActor(formID: 0x300)
        let index = RuntimeReferenceIndex(entries: [
            RuntimeReferenceEntry(
                key: .plugin(name: "skyrim.esm", objectID: 0x200),
                formID: reference.formID,
                isPersistent: false,
                record: .reference(reference)
            ),
            RuntimeReferenceEntry(
                key: .plugin(name: "skyrim.esm", objectID: 0x300),
                formID: actor.formID,
                isPersistent: true,
                record: .actor(actor)
            )
        ])
        let referenceEntry = try #require(index.entry(for: FormID(0x200)))
        #expect(referenceEntry.placedReference?.placement.position == SIMD3(1, 2, 3))
        #expect(referenceEntry.placedActor == nil)
        let actorEntry = try #require(index.entry(for: FormID(0x300)))
        #expect(actorEntry.placedActor?.base == FormID(0x101))
        #expect(actorEntry.placedReference == nil)
    }

    // MARK: - Duplicates and ordering

    @Test func duplicateKeysCollapseToTheLastEntry() throws {
        let index = try RuntimeReferenceIndex(entries: [
            entry(formID: 0x200, isPersistent: false),
            entry(formID: 0x200, isPersistent: true)
        ])
        #expect(index.count == 1)
        let survivor = try #require(index[.plugin(name: "skyrim.esm", objectID: 0x200)])
        #expect(survivor.isPersistent)
    }

    @Test func generatedAndPluginKeysCoexist() throws {
        let reference = try placedReference(formID: 0x200)
        let generated = RuntimeReferenceEntry(
            key: .generated(7),
            formID: FormID(0),
            isPersistent: false,
            record: .reference(reference)
        )
        let index = try RuntimeReferenceIndex(entries: [generated, entry(formID: 0x200)])
        #expect(index.count == 2)
        #expect(index[.generated(7)] != nil)
        #expect(index[.plugin(name: "skyrim.esm", objectID: 0x200)] != nil)
    }

    @Test func sortedKeysFollowReferenceKeyTotalOrder() throws {
        var entries = try [
            entry(formID: 0x203, plugin: "update.esm"),
            entry(formID: 0x201),
            entry(formID: 0x202)
        ]
        for (sequence, raw) in [(UInt64(2), UInt32(0x9000_0001)), (UInt64(1), 0x9000_0002)] {
            try entries.append(RuntimeReferenceEntry(
                key: .generated(sequence),
                formID: FormID(raw),
                isPersistent: false,
                record: .reference(placedReference(formID: raw))
            ))
        }
        let index = RuntimeReferenceIndex(entries: entries)
        #expect(index.sortedKeys() == [
            .plugin(name: "skyrim.esm", objectID: 0x201),
            .plugin(name: "skyrim.esm", objectID: 0x202),
            .plugin(name: "update.esm", objectID: 0x203),
            .generated(1),
            .generated(2)
        ])
        // Insertion order must not reach the output: the same entries in a
        // different order produce the same walk.
        let reversed = RuntimeReferenceIndex(entries: entries.reversed())
        #expect(reversed.sortedKeys() == index.sortedKeys())
        #expect(reversed.sortedEntries().map(\.formID) == index.sortedEntries().map(\.formID))
    }
}
