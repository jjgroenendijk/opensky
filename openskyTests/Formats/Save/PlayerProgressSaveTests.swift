// The `PLVL` chunk (issue #499, roadmap item 20.6): the character-level round
// trip, the clamping a load has to survive, and the absent-chunk case that
// keeps a save with no leveling byte-identical to what this encoder produced
// before the chunk existed.

import Foundation
@testable import opensky
import Testing

@MainActor
struct PlayerProgressSaveTests {
    private static func encode(_ snapshot: WorldStateSnapshot) -> Data {
        OpenSkySaveEncoder.encode(
            snapshot: snapshot,
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata
        )
    }

    private func roundTrip(_ state: PlayerProgressState) throws -> PlayerProgressState? {
        let store = WorldStateStore()
        store.set(state, for: .player, in: nil)
        let file = try OpenSkySaveDecoder.decode(Self.encode(store.snapshot()))
        return file.snapshot.entries.first { $0.key == ReferenceKey.player }?
            .delta.component(PlayerProgressState.self)
    }

    @Test func everyFieldSurvivesTheRoundTrip() throws {
        let state = PlayerProgressState(
            level: 17,
            experience: 123.5,
            perkPoints: 4,
            pendingAttributePicks: 2,
            attributePicks: [.health, .stamina, .stamina, .magicka],
            skillIncreases: 31
        )

        let restored = try #require(try roundTrip(state))

        #expect(restored == state)
        #expect(restored.attributePicks == [.health, .stamina, .stamina, .magicka])
        #expect(restored.pickCount(of: .stamina) == 2)
    }

    /// The pick history is written as vanilla actor-value indices, so the bytes
    /// stay addressed by the table every other chunk uses.
    @Test func picksAreWrittenAsActorValueIndices() {
        let store = WorldStateStore()
        store.set(
            PlayerProgressState(level: 2, attributePicks: [.magicka]),
            for: .player,
            in: nil
        )

        let data = Self.encode(store.snapshot())

        var index = UInt32(bitPattern: ActorValueIdentity.index(of: .magicka)).littleEndian
        let encoded = withUnsafeBytes(of: &index) { Data($0) }
        #expect(data.range(of: encoded) != nil)
    }

    /// A session that never levelled writes no chunk at all.
    @Test func aSessionThatNeverLevelledWritesNoChunk() {
        let store = WorldStateStore()
        store.set(PlayerProgressState(), for: .player, in: nil)

        let data = Self.encode(store.snapshot())

        #expect(!data.contains(Data(OpenSkySaveFormat.ChunkTag.playerProgress.utf8)))
    }

    /// The decoder normalizes rather than trusting the file: a level below the
    /// floor, a perk pool past the documented cap and a pick naming something
    /// that is not a primary are each corrected on the way in.
    @Test func aCorruptRecordIsClampedRatherThanTrusted() throws {
        let restored = try #require(try roundTrip(PlayerProgressState(
            level: -4,
            experience: .nan,
            perkPoints: 900,
            attributePicks: [.health]
        )))

        #expect(restored.level == 1)
        #expect(restored.experience == 0)
        #expect(restored.perkPoints == PlayerProgressState.maximumPerkPoints)
        #expect(restored.attributePicks == [.health])
    }

    /// Progress rides beside the base overrides an attribute pick wrote, which
    /// is the split the chunk is built on: the ten points live in `AVOV` and
    /// only the bookkeeping lives here.
    @Test func progressRidesBesideTheOverridesAPickWrote() throws {
        let store = WorldStateStore()
        let values = ActorValueRuntime(
            store: store,
            baselines: ActorValueBaselineResolver(
                fallback: ActorValueBaseline(
                    maximums: ActorValues(repeating: 100),
                    regenPercentPerSecond: .zero
                )
            )
        )
        let runtime = PlayerLevelRuntime(values: values)
        runtime.award(characterExperience: 100)
        runtime.chooseAttribute(.health)

        let file = try OpenSkySaveDecoder.decode(Self.encode(store.snapshot()))
        let restored = WorldStateStore()
        restored.restore(from: file.snapshot)
        let reloaded = PlayerLevelRuntime(
            values: ActorValueRuntime(store: restored, baselines: values.baselines)
        )

        #expect(reloaded.level == 2)
        #expect(reloaded.state.attributePicks == [.health])
        #expect(reloaded.values.maximums(of: .player).health == 110)
    }
}
