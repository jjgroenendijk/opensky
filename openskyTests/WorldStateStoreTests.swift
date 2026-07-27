// WorldStateStore unit tests (issue #159): component round-trips, reset,
// dirty tracking, the bounded change journal, snapshot determinism and
// generated-key allocation.
//
// The store is @MainActor, so the suite is too. Every fixture is synthetic and
// built in code — the baseline tests decode REFR/ACHR records straight from
// ESMFixture bytes, the same shape RuntimeReferenceIndexTests uses.

import Foundation
@testable import opensky
import simd
import Testing

@MainActor
struct WorldStateStoreTests {
    // MARK: - Fixtures

    private let whiterun = CellSceneLocation.exterior(CellCoordinate(x: 5, y: -1))
    private let riverwood = CellSceneLocation.exterior(CellCoordinate(x: 6, y: -1))
    private let inn = CellSceneLocation.interior(FormID(0x1234))

    private func key(_ objectID: UInt32, plugin: String = "skyrim.esm") -> ReferenceKey {
        .plugin(name: plugin, objectID: objectID)
    }

    private func record(_ bytes: Data) throws -> ESMRecord {
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("fixture did not produce a record")
        }
        return record
    }

    private func placementFields(position: SIMD3<Float>, scale: Float?) -> Data {
        var name = Data()
        name.appendUInt32(0x100)
        var data = Data()
        for value in [position.x, position.y, position.z, 0, 0, 0] {
            data.appendFloat32(value)
        }
        var fields = ESMFixture.field("NAME", name) + ESMFixture.field("DATA", data)
        if let scale {
            var scaleData = Data()
            scaleData.appendFloat32(scale)
            fields += ESMFixture.field("XSCL", scaleData)
        }
        return fields
    }

    private func referenceEntry(
        objectID: UInt32 = 0x200,
        position: SIMD3<Float> = SIMD3(1, 2, 3),
        scale: Float? = 2
    ) throws -> RuntimeReferenceEntry {
        let bytes = ESMFixture.record(
            "REFR",
            formID: objectID,
            data: placementFields(position: position, scale: scale)
        )
        return try RuntimeReferenceEntry(
            key: key(objectID),
            formID: FormID(objectID),
            isPersistent: false,
            record: .reference(PlacedReference(record: record(bytes)))
        )
    }

    private func actorEntry(objectID: UInt32 = 0x300, initiallyDisabled: Bool) throws
        -> RuntimeReferenceEntry
    {
        // Record-header flag 0x800 is `initiallyDisabled`.
        let bytes = ESMFixture.record(
            "ACHR",
            formID: objectID,
            flags: initiallyDisabled ? 0x800 : 0,
            data: placementFields(position: SIMD3(4, 5, 6), scale: nil)
        )
        return try RuntimeReferenceEntry(
            key: key(objectID),
            formID: FormID(objectID),
            isPersistent: true,
            record: .actor(PlacedActor(record: record(bytes)))
        )
    }

    private func transform(_ x: Float) -> ReferenceTransformOverride {
        ReferenceTransformOverride(position: SIMD3(x, 0, 0), scale: 1)
    }

    // MARK: - Component round-trips

    @Test func storesAndReadsBackEveryComponentKind() {
        let store = WorldStateStore()
        let reference = key(0x200)
        #expect(store.set(ReferenceEnableState.disabled, for: reference, in: whiterun))
        #expect(store.set(transform(9), for: reference, in: whiterun))
        #expect(store.set(
            ReferenceActivationState(activationCount: 2, isOpen: true, lastActivator: key(0x14)),
            for: reference,
            in: whiterun
        ))
        #expect(store.set(ReferenceDeletionState.deleted, for: reference, in: whiterun))

        #expect(store.component(ReferenceEnableState.self, for: reference)?.isEnabled == false)
        #expect(store.component(ReferenceTransformOverride.self, for: reference) == transform(9))
        let activation = store.component(ReferenceActivationState.self, for: reference)
        #expect(activation?.activationCount == 2)
        #expect(activation?.isOpen == true)
        #expect(activation?.lastActivator == key(0x14))
        #expect(store.component(ReferenceDeletionState.self, for: reference)?.isDeleted == true)
        #expect(store.delta(for: reference)?.sortedKinds == WorldStateComponentKind.allCases)
    }

    @Test func componentsOfCleanReferenceAreAbsent() {
        let store = WorldStateStore()
        #expect(store.component(ReferenceEnableState.self, for: key(0x200)) == nil)
        #expect(store.delta(for: key(0x200)) == nil)
        #expect(store.isDirty(key(0x200)) == false)
        #expect(store.dirtyCount == 0)
    }

    @Test func settingTheSameValueTwiceIsANoOp() {
        let store = WorldStateStore()
        #expect(store.set(ReferenceEnableState.disabled, for: key(0x200), in: whiterun))
        #expect(store.set(ReferenceEnableState.disabled, for: key(0x200), in: whiterun) == false)
        #expect(store.journalEntries.count == 1)
        #expect(store.set(ReferenceEnableState.enabled, for: key(0x200), in: whiterun))
        #expect(store.journalEntries.count == 2)
    }

    @Test func unknownKeysAreMutableWithoutError() {
        // A script may disable an object in a cell that has never loaded, so an
        // unrecognized key is state, not a failure.
        let store = WorldStateStore()
        #expect(store.set(ReferenceDeletionState.deleted, for: .generated(99)))
        #expect(store.isDirty(.generated(99)))
        #expect(store.dirtyCount == 1)
        #expect(store.unattributedDirtyCount == 1)
    }

    // MARK: - Reset

    @Test func perComponentResetLeavesTheOtherComponents() {
        let store = WorldStateStore()
        let reference = key(0x200)
        store.set(ReferenceEnableState.disabled, for: reference, in: whiterun)
        store.set(transform(3), for: reference, in: whiterun)
        #expect(store.reset(.enableState, for: reference))
        #expect(store.component(ReferenceEnableState.self, for: reference) == nil)
        #expect(store.component(ReferenceTransformOverride.self, for: reference) == transform(3))
        #expect(store.isDirty(reference))
        #expect(store.dirtyCount(in: whiterun) == 1)
    }

    @Test func resettingTheLastComponentClearsTheReference() {
        let store = WorldStateStore()
        let reference = key(0x200)
        store.set(ReferenceEnableState.disabled, for: reference, in: whiterun)
        #expect(store.reset(.enableState, for: reference))
        #expect(store.delta(for: reference) == nil)
        #expect(store.dirtyCount == 0)
        #expect(store.dirtyCount(in: whiterun) == 0)
        // A second reset changes nothing and reports so rather than failing.
        #expect(store.reset(.enableState, for: reference) == false)
        #expect(store.reset(reference) == false)
    }

    @Test func wholesaleResetDropsEveryComponent() {
        let store = WorldStateStore()
        let reference = key(0x200)
        store.set(ReferenceEnableState.disabled, for: reference, in: whiterun)
        store.set(transform(3), for: reference, in: whiterun)
        store.set(ReferenceActivationState(activationCount: 1), for: reference, in: whiterun)
        store.set(ReferenceDeletionState.deleted, for: reference, in: whiterun)
        #expect(store.reset(reference))
        #expect(store.delta(for: reference) == nil)
        #expect(store.dirtyCount == 0)
        // One journal entry per cleared component, in allCases order.
        let resets = store.journalEntries.filter(\.isReset)
        #expect(resets.map(\.kind) == WorldStateComponentKind.allCases)
    }

    @Test func resetAllClearsEveryReference() {
        let store = WorldStateStore()
        store.set(ReferenceEnableState.disabled, for: key(0x200), in: whiterun)
        store.set(transform(1), for: key(0x201), in: riverwood)
        store.resetAll()
        #expect(store.dirtyCount == 0)
        #expect(store.dirtyCountsByCellLocation.isEmpty)
        #expect(store.snapshot() == WorldStateSnapshot.empty)
    }

    // MARK: - Baseline re-derivation

    @Test func resetRestoresTheBaselineDerivedFromTheRecord() throws {
        let store = WorldStateStore()
        let entry = try referenceEntry(position: SIMD3(1, 2, 3), scale: 2)
        let baseline = store.resolvedState(for: entry)
        #expect(baseline.transform.position == SIMD3(1, 2, 3))
        #expect(baseline.transform.scale == 2)
        #expect(baseline.isDirty == false)
        #expect(baseline.isVisible)

        store.set(transform(42), for: entry.key, in: whiterun)
        store.set(ReferenceDeletionState.deleted, for: entry.key, in: whiterun)
        let mutated = store.resolvedState(for: entry)
        #expect(mutated.transform.position == SIMD3(42, 0, 0))
        #expect(mutated.overriddenKinds == [.transform, .deletion])
        #expect(mutated.isVisible == false)

        store.reset(entry.key)
        #expect(store.resolvedState(for: entry) == baseline)
    }

    @Test func actorBaselineHonoursTheInitiallyDisabledFlag() throws {
        let store = WorldStateStore()
        let hidden = try actorEntry(objectID: 0x300, initiallyDisabled: true)
        let visible = try actorEntry(objectID: 0x301, initiallyDisabled: false)
        #expect(store.resolvedState(for: hidden).enableState == .disabled)
        #expect(store.resolvedState(for: visible).enableState == .enabled)
        // Enabling the hidden actor overrides the record flag.
        store.set(ReferenceEnableState.enabled, for: hidden.key, in: inn)
        let resolved = store.resolvedState(for: hidden)
        #expect(resolved.enableState == .enabled)
        #expect(resolved.overriddenKinds == [.enableState])
    }

    // MARK: - Dirty tracking

    @Test func dirtyCountsSplitPerCellAndGlobally() {
        let store = WorldStateStore()
        store.set(ReferenceEnableState.disabled, for: key(0x200), in: whiterun)
        store.set(transform(1), for: key(0x201), in: whiterun)
        store.set(transform(2), for: key(0x202), in: riverwood)
        store.set(ReferenceDeletionState.deleted, for: key(0x203))

        #expect(store.dirtyCount == 4)
        #expect(store.dirtyCount(in: whiterun) == 2)
        #expect(store.dirtyCount(in: riverwood) == 1)
        #expect(store.dirtyCount(in: inn) == 0)
        #expect(store.unattributedDirtyCount == 1)
        #expect(store.sortedDirtyKeys(in: whiterun) == [key(0x200), key(0x201)])
        #expect(store.sortedDirtyKeys() == [
            key(0x200), key(0x201), key(0x202), key(0x203)
        ])
    }

    @Test func dirtyCountsReturnToZeroAfterReset() {
        let store = WorldStateStore()
        store.set(ReferenceEnableState.disabled, for: key(0x200), in: whiterun)
        store.set(transform(1), for: key(0x201), in: whiterun)
        store.reset(key(0x200))
        #expect(store.dirtyCount(in: whiterun) == 1)
        store.reset(key(0x201))
        #expect(store.dirtyCount(in: whiterun) == 0)
        #expect(store.dirtyCount == 0)
        #expect(store.dirtyCountsByCellLocation.isEmpty)
    }

    @Test func mutatingUnderANewCellMovesThePerCellCount() {
        // A persistent reference carried through a door keeps one delta, so the
        // per-cell counts must move rather than double-count it.
        let store = WorldStateStore()
        store.set(ReferenceEnableState.disabled, for: key(0x200), in: whiterun)
        store.set(transform(1), for: key(0x200), in: inn)
        #expect(store.dirtyCount == 1)
        #expect(store.dirtyCount(in: whiterun) == 0)
        #expect(store.dirtyCount(in: inn) == 1)
    }

    // MARK: - Mutation hook (issue #160)

    @Test func mutationHookFiresWithTheCellAndTheSequenceForEveryChange() {
        let store = WorldStateStore()
        var observed: [(CellSceneLocation?, UInt64)] = []
        store.onMutation = { location, sequence in
            observed.append((location, sequence))
        }

        store.set(ReferenceEnableState.disabled, for: key(0x200), in: whiterun)
        store.set(transform(1), for: key(0x201), in: inn)
        store.set(ReferenceEnableState.disabled, for: key(0x202))
        store.reset(.enableState, for: key(0x200))

        #expect(observed.map(\.0) == [whiterun, inn, nil, whiterun])
        // The sequence handed out is the one a snapshot taken right after the
        // mutation carries. Journal numbering starts at 1, so the first change
        // hands out 2: the snapshot that follows it is already past entry 1.
        #expect(observed.map(\.1) == [2, 3, 4, 5])
        #expect(store.nextJournalSequence == 5)
    }

    @Test func mutationHookStaysSilentForAWriteThatChangesNothing() {
        let store = WorldStateStore()
        store.set(ReferenceEnableState.disabled, for: key(0x200), in: whiterun)
        var fireCount = 0
        store.onMutation = { _, _ in fireCount += 1 }

        store.set(ReferenceEnableState.disabled, for: key(0x200), in: whiterun)
        store.reset(.transform, for: key(0x200))

        #expect(fireCount == 0)
    }

    @Test func mutationHookFiresOncePerClearedComponentOnAWholeReferenceReset() {
        let store = WorldStateStore()
        store.set(ReferenceEnableState.disabled, for: key(0x200), in: whiterun)
        store.set(transform(1), for: key(0x200), in: whiterun)
        var observed: [UInt64] = []
        store.onMutation = { _, sequence in observed.append(sequence) }

        store.reset(key(0x200))

        #expect(observed == [4, 5])
        #expect(store.dirtyCount == 0)
    }
}
