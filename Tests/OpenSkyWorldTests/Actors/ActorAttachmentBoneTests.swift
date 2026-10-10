// Which skeleton node each equipped weapon hangs from: a hand node, with a sheath
// node by animation type that the pose moves it onto, and the left hand for dual wield.

@testable import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
import simd
import Testing

struct ActorAttachmentBoneTests {
    @Test func sheathNodeFollowsTheAnimationType() {
        let node = ActorAttachmentBone.sheathNode(for:)
        #expect(node(.oneHandSword) == "WeaponSword")
        #expect(node(.oneHandDagger) == "WeaponDagger")
        #expect(node(.twoHandAxe) == "WeaponBack")
        #expect(node(.crossbow) == "WeaponBow")
        #expect(node(.other) == nil)
        #expect(node(nil) == nil)
    }

    @Test func sheathingMovesTheHandNodeOntoTheSheathNode() {
        let bones = SkeletonBoneIndex(names: ["Weapon", "WeaponSword", "Head"])
        let hand = MatrixMath.translation(SIMD3(1, 0, 0))
        let hip = MatrixMath.translation(SIMD3(0, 2, 0))
        let pose = SkeletonPose(bones: bones, matrices: [hand, hip, hand])
        let nodes = ["Weapon": "WeaponSword", "Shield": "ShieldBack"]

        let sheathed = WeaponSheathing.apply(nodes, drawn: false, to: pose)
        let drawn = WeaponSheathing.apply(nodes, drawn: true, to: pose)

        #expect(sheathed.matrices == [hip, hip, hand])
        #expect(drawn.matrices == pose.matrices)
    }

    @Test func aSecondOneHandedWeaponGoesToTheLeftHand() throws {
        let mace = EquippableItem(
            occupancy: EquipmentOccupancy(hands: .rightHand),
            modelPath: "mace.nif", animationType: .oneHandMace
        )
        let base = makeResolver()
        let resolver = ActorVisualResolver(
            races: base.races,
            armors: base.armors,
            armorAddons: base.armorAddons,
            outfits: base.outfits,
            leveledItems: base.leveledItems,
            formIDResolver: base.formIDResolver,
            equipment: makeEquipmentCatalog(extra: [0x620: mace])
        )
        let visual = try resolver.resolve(
            appearance: appearance(), equipped: [FormID(0x600), FormID(0x620)]
        )

        #expect(visual.attachments.map(\.bone) == ["Weapon", "Shield"])
        #expect(visual.sheathNodes == ["Shield": "WeaponMace"])
    }
}
