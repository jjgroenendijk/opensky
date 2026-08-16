// The `SPLB` chunk (issue #470, roadmap item 19.7): the spellbook round trip,
// the readied-hand invariant a load has to restore, and the absent-chunk case
// that keeps a save with no spellbook byte-identical to what this encoder
// produced before the chunk existed.

import Foundation
@testable import opensky
import Testing

@MainActor
struct SpellbookSaveTests {
    private let healing = SpellbookFixture.key(SpellbookFixture.Spell.healing)
    private let master = SpellbookFixture.key(SpellbookFixture.Spell.masterHeal)
    private let tome = SpellbookFixture.key(SpellbookFixture.Book.healingTome)
    private let power = SpellbookFixture.key(SpellbookFixture.Spell.dragonskin)

    /// The encoder's two required header arguments, from the shared fixture, so
    /// every call here differs only in the snapshot.
    private static func encode(_ snapshot: WorldStateSnapshot) -> Data {
        OpenSkySaveEncoder.encode(
            snapshot: snapshot,
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata
        )
    }

    private func roundTrip(_ state: SpellbookState) throws -> SpellbookState? {
        let store = WorldStateStore()
        store.set(state, for: .player, in: nil)
        let data = Self.encode(store.snapshot())
        let file = try OpenSkySaveDecoder.decode(data)
        return file.snapshot.entries.first { $0.key == ReferenceKey.player }?
            .delta.component(SpellbookState.self)
    }

    @Test func aWholeSpellbookSurvivesTheRoundTrip() throws {
        let state = SpellbookState(
            known: [healing, master, power],
            readBooks: [tome],
            leftHand: master,
            rightHand: master,
            powerDays: [power: 7]
        )

        let restored = try #require(try roundTrip(state))

        #expect(restored == state)
        #expect(restored.known == [healing, master, power].sorted())
        #expect(restored.hasRead(tome))
        #expect(restored.spell(in: .left) == master)
        #expect(restored.spell(in: .right) == master)
        #expect(restored.hasSpentPower(power, onDay: 7))
    }

    @Test func aSessionThatLearnedNothingWritesNoChunk() {
        let store = WorldStateStore()

        let data = Self.encode(store.snapshot())

        #expect(!data.contains(Data(OpenSkySaveFormat.ChunkTag.spellbooks.utf8)))
    }

    /// The invariant the component enforces on the way in, which is what makes
    /// it the decoder's entry point: a hand naming a spell the reader no longer
    /// knows is cleared rather than restored dangling.
    @Test func aReadiedHandNamingAnUnknownSpellIsClearedOnLoad() throws {
        // Built by hand rather than through `equip`, because this is the state
        // a file edited under a different load order would carry.
        let state = SpellbookState(known: [healing], leftHand: healing, rightHand: healing)
        let store = WorldStateStore()
        store.set(state, for: .player, in: nil)
        let data = Self.encode(store.snapshot())
        let file = try OpenSkySaveDecoder.decode(data)
        let restored = try #require(
            file.snapshot.entries
                .first { $0.key == ReferenceKey.player }?
                .delta.component(SpellbookState.self)
        )

        let forgotten = restored.forgetting(healing)

        #expect(forgotten.leftHand == nil)
        #expect(forgotten.rightHand == nil)
        #expect(forgotten.isEmpty)
    }

    /// A spellbook is the only delta an actor has, so its entry has to be added
    /// to the snapshot rather than laid over an existing `RDLT` one.
    @Test func aSpellbookOnlyActorGetsAnEntryOfItsOwn() throws {
        let store = WorldStateStore()
        let actor = ReferenceKey.plugin(name: "base.esm", objectID: 0x1234)
        store.set(SpellbookState(known: [healing]), for: actor, in: nil)

        let file = try OpenSkySaveDecoder.decode(Self.encode(store.snapshot()))

        let entry = try #require(file.snapshot.entries.first { $0.key == actor })
        #expect(entry.delta.component(SpellbookState.self)?.known == [healing])
    }
}
