// A mine burns a 0.2 s fuse once a trigger comes near, blinks faster as the fuse runs
// out, and stops checking the player after one failed Calculate Mine Explode Chance roll.

@testable import OpenSkyFormatsESM
@testable import OpenSkyMagic
@testable import OpenSkyMagicInterface
import OpenSkyPhysics
import Testing

@MainActor
struct MineFuseTests {
    private static let wolf = ReferenceKey.plugin(name: "base.esm", objectID: 0x0901)

    @Test func theFuseBurnsForAFifthOfASecond() {
        var fuse = MineFuse()
        let idle = fuse.burn(1)
        #expect(!idle)
        fuse.notice(Self.wolf) { false }
        #expect(fuse.isBurning)
        #expect(fuse.trigger == Self.wolf)
        let early = fuse.burn(0.1)
        #expect(!early)
        let done = fuse.burn(0.1)
        #expect(done)
    }

    @Test func aSecondNoticeKeepsTheFirstTrigger() {
        var fuse = MineFuse()
        fuse.notice(Self.wolf) { true }
        fuse.notice(.player) { true }
        #expect(fuse.trigger == Self.wolf)
    }

    @Test func aFailedRollMakesTheMineIgnoreThePlayer() {
        var fuse = MineFuse()
        var rolls = 0
        fuse.notice(.player) {
            rolls += 1
            return false
        }
        #expect(fuse.ignoresPlayer)
        #expect(!fuse.isBurning)
        fuse.notice(.player) {
            rolls += 1
            return true
        }
        #expect(rolls == 1)
        #expect(!fuse.isBurning)
        fuse.notice(Self.wolf) { false }
        #expect(fuse.trigger == Self.wolf)
    }

    @Test func theLightBlinksFasterAsTheFuseRunsOut() {
        #expect(MineFuse.blinkInterval(remaining: 5) == 0.25)
        #expect(abs(MineFuse.blinkInterval(remaining: 1) - 0.175) < 0.0001)
        #expect(MineFuse.blinkInterval(remaining: 0) == 0.1)
        var fuse = MineFuse()
        fuse.notice(Self.wolf) { false }
        _ = fuse.burn(0.15)
        #expect(fuse.isLit)
    }

    @Test func aRollBelowTheChancePasses() {
        #expect(MineFuse.playerPasses(chance: 100, roll: 99.9))
        #expect(!MineFuse.playerPasses(chance: 0, roll: 0))
        #expect(!MineFuse.playerPasses(chance: 50, roll: 50))
    }

    @Test func nearbyTriggersAreSortedNearestFirst() {
        var rune = PlacedRune(
            payload: SpellPayload(
                spell: .plugin(name: "base.esm", objectID: 0x600), sourcePlugin: "Base.esm",
                caster: .player, entries: [], isHostile: true, ignoresResistance: false,
                projectile: nil, name: "Rune"
            ),
            position: .zero, proximity: 150
        )
        rune.age = 1
        let near = MeleeTarget(key: Self.wolf, feet: SIMD3(50, 0, 0))
        let other = ReferenceKey.plugin(name: "base.esm", objectID: 0x0902)
        let farther = MeleeTarget(key: other, feet: SIMD3(120, 0, 0))
        #expect(RuneCore.nearby(rune, among: [farther, near], settings: .vanilla).map(\.key)
            == [Self.wolf, other])
        rune.fuse.notice(.player) { false }
        let player = MeleeTarget(key: .player, feet: SIMD3(10, 0, 0))
        #expect(RuneCore.nearby(rune, among: [player], settings: .vanilla).isEmpty)
    }
}
