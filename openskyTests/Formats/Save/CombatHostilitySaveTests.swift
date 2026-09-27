// CBTS chunk tests (issue #374): the additive hostility chunk in the OpenSky
// native save container.
//
// The same promises `AVAL` and `DETH` make, for the same reasons: a save
// carrying an angry actor must still load in a build that knows nothing about
// the chunk, and `RDLT` must gain nothing so an actor whose only component is
// its hostility leaves no entry there for an older build to restore as an empty
// reference.
//
// Beyond the round trip, this suite pins the item's stated persistence choice: a
// fight saved mid-swing reloads with the opponent still hostile, because that is
// what makes a reloaded fight still a fight, while an actor calmed back down
// keeps its component rather than being written out and re-reading as neutral by
// accident.

import Foundation
@testable import opensky
import Testing

@MainActor
struct CombatHostilitySaveTests {
    private let bandit = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0001_3BAC)
    private let calmed = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0001_3BAD)

    /// A snapshot with three shapes: a hostile actor whose only delta is its
    /// regard for the player, one explicitly returned to neutral, and an
    /// ordinary reference that was never in a fight.
    private func snapshot() -> WorldStateSnapshot {
        let entries = [
            OpenSkySaveFixture.entry(
                key: bandit,
                cell: OpenSkySaveFixture.whiterun,
                components: [ActorCombatState.hostile.erased]
            ),
            OpenSkySaveFixture.entry(
                key: calmed,
                cell: OpenSkySaveFixture.whiterun,
                components: [ActorCombatState.neutral.erased]
            ),
            OpenSkySaveFixture.entry(
                key: .plugin(name: "skyrim.esm", objectID: 1),
                cell: OpenSkySaveFixture.riverwood,
                components: [ReferenceDeletionState.deleted.erased]
            )
        ]
        return WorldStateSnapshot(
            entries: entries.sorted { $0.key < $1.key },
            nextGeneratedSequence: 5,
            sequence: 11
        )
    }

    private func encode(_ snapshot: WorldStateSnapshot) -> Data {
        OpenSkySaveEncoder.encode(
            snapshot: snapshot,
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata
        )
    }

    // MARK: - Round trip

    @Test func hostilitySurvivesAnEncodeAndDecode() throws {
        let original = snapshot()
        let file = try OpenSkySaveDecoder.decode(encode(original))
        #expect(file.snapshot == original)

        let delta = try #require(file.snapshot[bandit])
        #expect(delta.sortedKinds == [.combat])
        #expect(delta.cell == OpenSkySaveFixture.whiterun)
        #expect(delta.component(ActorCombatState.self) == .hostile)
    }

    /// An actor calmed back down keeps its component. Neutral is the default an
    /// untouched actor reads, but writing this one out would make a reload find
    /// it angry again.
    @Test func anActorReturnedToNeutralKeepsItsComponent() throws {
        let file = try OpenSkySaveDecoder.decode(encode(snapshot()))
        let state = try #require(file.snapshot[calmed]?.component(ActorCombatState.self))
        #expect(state.hostility == .neutral)
    }

    /// Restoring a decoded save into a live store leaves the opponent hostile,
    /// which is what makes a fight saved mid-swing reload as a fight.
    @Test func restoringASaveBringsTheFightBack() throws {
        let file = try OpenSkySaveDecoder.decode(encode(snapshot()))
        let store = WorldStateStore()
        store.restore(from: file.snapshot)
        #expect(store.component(ActorCombatState.self, for: bandit) == .hostile)
        #expect(store.snapshot() == file.snapshot)
    }

    @Test func decodedEntriesStayInReferenceKeyOrder() throws {
        let file = try OpenSkySaveDecoder.decode(encode(snapshot()))
        #expect(file.snapshot.keys == file.snapshot.keys.sorted())
    }

    /// Two stores that reached the same end state write identical bytes.
    @Test func encodingIsDeterministic() {
        #expect(encode(snapshot()) == encode(snapshot()))
    }

    // MARK: - Additive-chunk tolerance

    /// A session in which nothing was provoked writes no `CBTS` chunk at all.
    @Test func aSaveWithNoFightCarriesNoChunk() {
        let encoded = encode(OpenSkySaveFixture.richSnapshot())
        #expect(OpenSkySaveFixture.offset(
            ofChunk: OpenSkySaveFormat.ChunkTag.combatStates, in: encoded
        ) == nil)
    }

    /// The older-build case: the same file with the chunk tag renamed to one
    /// nothing knows decodes cleanly, losing only the hostility.
    @Test func anUnknownChunkTagIsSkippedByItsLength() throws {
        let encoded = encode(snapshot())
        let offset = try #require(OpenSkySaveFixture.offset(
            ofChunk: OpenSkySaveFormat.ChunkTag.combatStates, in: encoded
        ))
        let renamed = OpenSkySaveFixture.patching(
            encoded, at: offset, with: Array("ZZZZ".utf8)
        )
        let file = try OpenSkySaveDecoder.decode(renamed)
        #expect(file.snapshot[bandit] == nil)
        #expect(file.snapshot[.plugin(name: "skyrim.esm", objectID: 1)] != nil)
    }

    /// `RDLT` must not carry a combat component, so an older build restores the
    /// world without one rather than failing on an unknown tag.
    @Test func rdltRejectsACombatComponentTag() {
        #expect(WorldStateComponentKind.combat.saveTag == nil)
    }

    // MARK: - Corruption

    @Test func anImpossibleEntryCountIsRejected() {
        var payload = BinaryWriter()
        payload.writeUInt32(0xFFFF_FFFF)
        #expect(throws: OpenSkySaveError.self) {
            try OpenSkySaveCombatDecoder.decodeCombatStates(payload.data)
        }
    }

    /// A hostility byte no build has defined decodes as neutral rather than
    /// throwing: a future third regard should load with that actor calm, not
    /// refuse the file.
    @Test func anUnknownHostilityByteDecodesAsNeutral() throws {
        var payload = BinaryWriter()
        payload.writeUInt32(1)
        payload.writeUInt8(OpenSkySaveFormat.KeyTag.generated)
        payload.writeUInt64(7)
        payload.writeUInt8(OpenSkySaveFormat.CellTag.absent)
        payload.writeUInt8(200)
        let entries = try OpenSkySaveCombatDecoder.decodeCombatStates(payload.data)
        #expect(entries.count == 1)
        #expect(entries.first?.state.hostility == .neutral)
    }
}
