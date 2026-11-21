// An attacking NPC refreshes its aim every 0.25 s, and every 0.1 s for the player
// inside the track band (docs/engine/combat-assist.md#npc-attack-tracking).

@testable import OpenSkyCombat
import OpenSkyFormatsESM
import Testing

struct CombatAttackTrackTests {
    private let npc = ReferenceKey.plugin(name: "test.esm", objectID: 0x10)

    @Test func theBandRunsFromReachPlus128ToReachPlus512() {
        #expect(!CombatAttackTrack.isInBand(distance: 200, reach: 100))
        #expect(CombatAttackTrack.isInBand(distance: 228, reach: 100))
        #expect(CombatAttackTrack.isInBand(distance: 612, reach: 100))
        #expect(!CombatAttackTrack.isInBand(distance: 613, reach: 100))
    }

    @Test func theAimHoldsBetweenRefreshes() {
        var track = CombatAttackTrack(target: npc, aim: .zero)
        let moved = SIMD3<Float>(50, 0, 0)
        #expect(track.advance(by: 0.2, targetFeet: moved, distance: 100, reach: 100) == .zero)
        #expect(track.advance(by: 0.05, targetFeet: moved, distance: 100, reach: 100) == moved)
        #expect(track.refreshes == 1)
    }

    @Test func thePlayerInTheBandIsRefreshedFaster() {
        var track = CombatAttackTrack(target: .player, aim: .zero)
        let moved = SIMD3<Float>(50, 0, 0)
        #expect(track.advance(by: 0.1, targetFeet: moved, distance: 300, reach: 100) == moved)
        var near = CombatAttackTrack(target: .player, aim: .zero)
        #expect(near.advance(by: 0.1, targetFeet: moved, distance: 100, reach: 100) == .zero)
    }
}
