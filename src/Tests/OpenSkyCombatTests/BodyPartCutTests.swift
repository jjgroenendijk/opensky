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

struct BodyPartCutRoundingTests {
    /// 75 × 33 / 100 is 24 after the whole-number cut: a roll of 24 no longer explodes.
    @Test func theScaledChanceDropsItsFraction() {
        let part = ExplodablePart(node: "Head", chance: 33, isChanceAbsolute: false)
        let cut = BodyPartCut.of(part, roll: 24, explodePercent: 75, dismemberChance: 50)
        #expect(cut == .sever)
    }

    @Test func theWeaponOnHitSettingChangesASuccess() {
        #expect(BodyPartCut.explode.applying(weaponOnHit: 0) == .explode)
        #expect(BodyPartCut.explode.applying(weaponOnHit: 1) == .sever)
        #expect(BodyPartCut.sever.applying(weaponOnHit: 2) == .explode)
        #expect(BodyPartCut.sever.applying(weaponOnHit: 3) == BodyPartCut.none)
        #expect(BodyPartCut.none.applying(weaponOnHit: 2) == BodyPartCut.none)
    }
}
