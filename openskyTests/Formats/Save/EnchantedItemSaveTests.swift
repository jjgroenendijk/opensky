// The ECHG save chunk (issue #472, roadmap item 19.9): round trip, additivity and
// the tolerance rules the container promises.
//
// A save is OpenSky's own format, so nothing here touches game data at all.

import Foundation
@testable import opensky
import Testing

struct EnchantedItemSaveTests {
    private let owner = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0001_3BAC)
    private let blade = FormID(0x0001_3987)
    private let ring = FormID(0x0009_1A00)

    private func snapshot(_ state: EnchantedItemState) -> WorldStateSnapshot {
        WorldStateSnapshot(
            entries: [
                OpenSkySaveFixture.entry(
                    key: owner,
                    cell: OpenSkySaveFixture.whiterun,
                    components: [state.erased]
                )
            ],
            nextGeneratedSequence: 1,
            sequence: 1
        )
    }

    private func encode(_ state: EnchantedItemState) -> Data {
        OpenSkySaveEncoder.encode(
            snapshot: snapshot(state),
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata
        )
    }

    private func roundTrip(_ state: EnchantedItemState) throws -> EnchantedItemState? {
        let file = try OpenSkySaveDecoder.decode(encode(state))
        return file.snapshot.entries
            .first { $0.key == owner }?
            .delta.component(EnchantedItemState.self)
    }

    /// The acceptance point: a drained weapon reloads drained, and a worn item
    /// reloads still owning the effects it established.
    @Test func chargeAndWornEffectsSurviveARoundTrip() throws {
        let state = EnchantedItemState(
            charges: [blade.rawValue: 72],
            wornEffects: [ring.rawValue: [3, 1, 2]]
        )
        let restored = try #require(try roundTrip(state))
        #expect(restored == state)
        #expect(restored.charge(of: blade) == 72)
        // Sorted on the way in, so re-encoding an unchanged owner is stable.
        #expect(restored.wornEffects(of: ring) == [1, 2, 3])
        #expect(restored.allWornSequences == [1, 2, 3])
    }

    /// An owner whose only delta is its enchanted items has no `RDLT` entry, so
    /// the merge is what puts the component back on a reference nothing else
    /// touched.
    @Test func anOwnerWithNoOtherDeltaStillRestores() throws {
        let state = EnchantedItemState(charges: [blade.rawValue: 5])
        let file = try OpenSkySaveDecoder.decode(encode(state))
        #expect(file.snapshot.entries.count == 1)
        #expect(file.snapshot.entries.first?.key == owner)
    }

    /// A session in which nothing enchanted fired and nothing enchanted was worn
    /// writes no chunk at all, so its bytes match what the encoder produced before
    /// the chunk existed.
    @Test func anEmptyStateWritesNoChunk() {
        let withState = encode(EnchantedItemState(charges: [blade.rawValue: 5]))
        let withoutState = encode(EnchantedItemState())
        #expect(!withoutState.contains(Data("ECHG".utf8)))
        #expect(withState.contains(Data("ECHG".utf8)))
        #expect(withState.count > withoutState.count)
    }

    /// Encoding is deterministic: two states that reached the same contents
    /// through different insertion orders write identical bytes.
    @Test func encodingIsOrderIndependent() {
        let one = EnchantedItemState(
            charges: [blade.rawValue: 10, ring.rawValue: 20],
            wornEffects: [ring.rawValue: [2, 1]]
        )
        let other = EnchantedItemState(
            charges: [ring.rawValue: 20, blade.rawValue: 10],
            wornEffects: [ring.rawValue: [1, 2]]
        )
        #expect(encode(one) == encode(other))
    }

    /// Nonsense normalizes rather than failing a load: a non-finite charge becomes
    /// zero and an item recorded as owning no effects is dropped.
    @Test func nonsensicalValuesNormalizeOnTheWayIn() throws {
        let state = EnchantedItemState(
            charges: [blade.rawValue: -1, ring.rawValue: .nan],
            wornEffects: [ring.rawValue: []]
        )
        #expect(state.charge(of: blade) == 0)
        #expect(state.charge(of: ring) == 0)
        #expect(state.wornEffects(of: ring).isEmpty)
        #expect(state.wornItems.isEmpty)
        let restored = try #require(try roundTrip(state))
        #expect(restored == state)
    }
}
