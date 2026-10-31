// Which skeleton node each equipped weapon or shield hangs from: a hand node, with a
// sheath node by animation type that the pose moves it onto, and the left hand for dual
// wield or a shield.

@testable import OpenSkyActorPresentation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldTesting
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
        let resolver = resolver(equipment: makeEquipmentCatalog(extra: [0x620: mace]))
        let visual = try resolver.resolve(
            appearance: appearance(), equipped: [FormID(0x600), FormID(0x620)]
        )

        #expect(visual.attachments.map(\.bone) == ["Weapon", "Shield"])
        #expect(visual.sheathNodes == ["Shield": "WeaponMace"])
    }

    /// A shield is a rigid model, so it rides the left-hand node and is not
    /// skinned to the body. The gloves fixture stands in for a shield here.
    @Test func aWornShieldRidesTheShieldNode() throws {
        let shield = EquippableItem(
            occupancy: EquipmentOccupancy(slots: BodySlots(rawValue: 0b10000), hands: .leftHand),
            modelPath: nil
        )
        let resolver = resolver(equipment: makeEquipmentCatalog(extra: [0x330: shield]))
        let visual = try resolver.resolve(appearance: appearance(), equipped: [FormID(0x330)])

        let held = ResolvedAttachment(modelPath: "gloves_m.nif", bone: "Shield")
        #expect(visual.attachments == [held])
        #expect(!visual.parts.map(\.modelPath).contains("gloves_m.nif"))
        #expect(visual.sheathNodes.isEmpty)
    }

    /// With no runtime equipped set, the NPC holds the weapon it carries beside its outfit.
    @Test func anOutfitWearerHoldsItsCarriedWeapon() throws {
        let visual = try makeResolver().resolve(
            appearance: appearance(outfit: 0x400),
            carried: CarriedItems(
                entries: [Container.Entry(
                    item: FormID(0x600), count: 1, owner: nil, ownerCondition: nil, condition: nil
                )],
                combatStyle: nil
            )
        )

        #expect(visual.attachments.map(\.modelPath) == ["sword.nif"])
        #expect(visual.parts.map(\.modelPath).contains("clothes_m.nif"))
    }

    /// Equipped arrows hang on the quiver node, drawn without the arrow on the string.
    @Test func equippedArrowsRideTheQuiverNode() throws {
        let arrows = EquippableItem(
            occupancy: EquipmentOccupancy(ammunition: true),
            modelPath: "arrow.nif", animationType: .bow, rating: 8
        )
        let resolver = resolver(equipment: makeEquipmentCatalog(extra: [0x630: arrows]))
        let visual = try resolver.resolve(appearance: appearance(), equipped: [FormID(0x630)])

        let quiver = ResolvedAttachment(
            modelPath: "arrow.nif",
            bone: "Quiver",
            subtree: "ArrowQuiver"
        )
        #expect(visual.attachments == [quiver])
        #expect(!visual.skips.contains { $0.subject == FormID(0x630) })
    }

    private func resolver(equipment: EquipmentCatalog) -> ActorVisualResolver {
        let base = makeResolver()
        return ActorVisualResolver(
            races: base.races,
            armors: base.armors,
            armorAddons: base.armorAddons,
            outfits: base.outfits,
            leveledItems: base.leveledItems,
            formIDResolver: base.formIDResolver,
            equipment: equipment
        )
    }
}
