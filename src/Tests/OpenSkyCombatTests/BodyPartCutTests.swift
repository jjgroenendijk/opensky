// The explode and dismember rolls of an explodable body part, from
// docs/engine/explosion-effects.md#exploding-body-parts.

import OpenSkyCombatInterface
import Testing

struct BodyPartCutTests {
    private static func cut(_ part: ExplodablePart, roll: Int) -> BodyPartCut {
        BodyPartCut.of(part, roll: roll, explodePercent: 75, dismemberChance: 50)
    }

    @Test func aScaledChanceUsesTheGamesPercentage() {
        // 75 × 40 / 100 = 30: a roll of 29 explodes, 30 does not.
        let part = ExplodablePart(node: "Head", chance: 40, isChanceAbsolute: false)
        #expect(Self.cut(part, roll: 29) == .explode)
        #expect(Self.cut(part, roll: 30) == .sever)
        #expect(Self.cut(part, roll: 50) == .none)
    }

    @Test func anAbsoluteChanceIsUsedAsItIs() {
        let part = ExplodablePart(node: "Head", chance: 40, isChanceAbsolute: true)
        #expect(Self.cut(part, roll: 39) == .explode)
        #expect(Self.cut(part, roll: 40) == .sever)
        let always = ExplodablePart(node: "Head", chance: 100, isChanceAbsolute: true)
        #expect(Self.cut(always, roll: 99) == .explode)
    }
}
