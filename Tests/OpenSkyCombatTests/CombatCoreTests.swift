// The combat rules over plain values: hands, bow, intent masking, health, the
// spell gates and the block source. The shell is in `CombatCoordinatorTests`.

@testable import OpenSkyActorsInterface
@testable import OpenSkyCombat
@testable import OpenSkyCombatInterface
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import Testing

struct CombatCoreTests {
    private static let sword = MeleeWeaponProfile(
        damage: 7, reach: 1, weapon: FormID(0x12EB7), handType: .sword
    )
    private static let dagger = MeleeWeaponProfile(
        damage: 4, reach: 0.7, weapon: FormID(0x1397E), handType: .dagger
    )
    private static let greatsword = MeleeWeaponProfile(
        damage: 15, reach: 1.3, weapon: FormID(0x1359D), handType: .greatsword
    )
    private static let bow = MeleeWeaponProfile(
        damage: 6, reach: 1, weapon: FormID(0x3B562), handType: .bow
    )

    @Test func nothingWornIsUnarmedHandToHand() {
        let hands = CombatCore.hands(worn: [], readied: .none)
        #expect(hands == CombatHands(weapon: .unarmed, offHand: .handToHand))
    }

    @Test func aShieldAloneFillsTheOffHand() {
        let hands = CombatCore.hands(worn: [.other, .shield], readied: .none)
        #expect(hands == CombatHands(weapon: .unarmed, offHand: .shield))
    }

    @Test func aTwoHandedWeaponFillsBothHands() {
        let hands = CombatCore.hands(worn: [.weapon(Self.greatsword), .shield], readied: .none)
        #expect(hands == CombatHands(weapon: Self.greatsword, offHand: .greatsword))
    }

    @Test func aSecondWeaponIsTheOffHandBeforeAShield() {
        let worn: [CombatWornItem] = [.weapon(Self.sword), .shield, .weapon(Self.dagger)]
        let hands = CombatCore.hands(worn: worn, readied: .none)
        #expect(hands == CombatHands(weapon: Self.sword, offHand: .dagger))
    }

    @Test func aReadiedSpellReplacesTheHandItIsIn() {
        let worn: [CombatWornItem] = [.weapon(Self.sword), .shield]
        let right = CombatCore.hands(worn: worn, readied: ReadiedHands(right: true, left: false))
        #expect(right == CombatHands(weapon: .readiedSpell, offHand: .shield))
        let left = CombatCore.hands(worn: worn, readied: ReadiedHands(right: false, left: true))
        #expect(left == CombatHands(weapon: Self.sword, offHand: .spell))
    }

    @Test func theBowIsTheFirstWornBow() {
        #expect(CombatCore.bow(worn: [.weapon(Self.sword), .weapon(Self.bow)]) == Self.bow)
        #expect(CombatCore.bow(worn: [.weapon(Self.sword), .shield]) == .unarmed)
    }

    @Test func aReadiedHandGivesUpItsButton() {
        let pressed = MeleeIntent(attack: true, block: true, toggleWeaponDrawn: true)
        let masked = CombatCore.meleeIntent(pressed, readied: ReadiedHands(right: true, left: true))
        #expect(masked == MeleeIntent(attack: false, block: false, toggleWeaponDrawn: true))
        #expect(CombatCore.meleeIntent(pressed, readied: .none) == pressed)
    }

    @Test func theArrowIsTheFirstCarriedItemThatFlies() {
        let arrow = ArcheryAmmunition(
            item: FormID(0x1397D),
            damage: 8,
            profile: ProjectileProfile(speed: 3600, gravityFactor: 0.35, range: 60000)
        )
        let carried = [FormID(0xF), FormID(0x1397D)]
        #expect(CombatCore.arrow(carried: carried) { $0 == arrow.item ? arrow : nil } == arrow)
        #expect(CombatCore.arrow(carried: [FormID(0xF)]) { _ in nil } == nil)
    }

    @Test func healthFractionIsClampedAndFullWithoutAMaximum() {
        #expect(CombatCore.healthFraction(current: 25, maximum: 100) == 0.25)
        #expect(CombatCore.healthFraction(current: -5, maximum: 100) == 0)
        #expect(CombatCore.healthFraction(current: 150, maximum: 100) == 1)
        #expect(CombatCore.healthFraction(current: 0, maximum: 0) == 1)
    }

    @Test func onlyAHostileDeliverableHandSpellIsAnOption() {
        let flames = Self.candidate(spell: 2)
        #expect(CombatCore.spellOption(flames) == flames.option)
        #expect(CombatCore.spellOption(Self.candidate(spell: 2, isSpell: false)) == nil)
        #expect(CombatCore.spellOption(Self.candidate(spell: 2, targetsSelf: true)) == nil)
        #expect(CombatCore.spellOption(Self.candidate(spell: 2, isDeliverable: false)) == nil)
        #expect(CombatCore.spellOption(Self.candidate(spell: 2, isHostile: false)) == nil)
        #expect(CombatCore.spellOption(Self.candidate(spell: 2, fitsHand: false)) == nil)
    }

    @Test func theCastingProfileKeepsOptionsInSpellOrder() {
        let facts = CombatCastingFacts(magicka: 80, spells: [
            Self.candidate(spell: 9),
            Self.candidate(spell: 5, isHostile: false),
            Self.candidate(spell: 3)
        ])
        let profile = CombatCore.castingProfile(facts)
        #expect(profile.magicka == 80)
        #expect(profile.options.map(\.spell) == [.generated(3), .generated(9)])
    }

    @Test func thePlayerBlocksFromItsGuardAndAnNPCFromItsMachine() {
        let npc = ReferenceKey.generated(7)
        #expect(CombatCore.block(of: .player, playerIsBlocking: true, machineBlock: nil) == .weapon)
        #expect(CombatCore
            .block(of: .player, playerIsBlocking: false, machineBlock: .weapon) == nil)
        #expect(CombatCore.block(of: npc, playerIsBlocking: true, machineBlock: nil) == nil)
        #expect(CombatCore
            .block(of: npc, playerIsBlocking: false, machineBlock: .weapon) == .weapon)
    }

    private static func candidate(
        spell: UInt64,
        isSpell: Bool = true,
        targetsSelf: Bool = false,
        isDeliverable: Bool = true,
        isHostile: Bool = true,
        fitsHand: Bool = true
    ) -> CombatSpellCandidate {
        CombatSpellCandidate(
            option: CombatSpellOption(spell: .generated(spell), cost: 14, range: 2048),
            isSpell: isSpell,
            targetsSelf: targetsSelf,
            isDeliverable: isDeliverable,
            isHostile: isHostile,
            fitsHand: fitsHand
        )
    }
}
