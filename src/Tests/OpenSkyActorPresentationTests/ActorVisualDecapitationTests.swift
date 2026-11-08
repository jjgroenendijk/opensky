// A decapitated look splits into a body and a head piece. Synthetic fixtures throughout.

@testable import OpenSkyActorPresentation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyWorldInterface
import OpenSkyWorldTesting
import Testing

struct ActorVisualDecapitationTests {
    private func part(_ armature: UInt32, _ model: String, _ slots: BodySlots) -> ResolvedBodyPart {
        ResolvedBodyPart(
            origin: .outfit(FormID(0x100)), armature: FormID(armature), modelPath: model,
            firstPersonModelPath: nil, slots: slots
        )
    }

    private func visual(parts: [ResolvedBodyPart]) -> ResolvedActorVisual {
        ResolvedActorVisual(
            appearance: appearance(),
            skeletonPath: "actors\\character\\character assets\\skeleton.nif",
            skin: FormID(0x200),
            equippedSlots: [.body],
            parts: parts,
            attachments: [ResolvedAttachment(modelPath: "weapons\\sword.nif", bone: "Weapon")],
            usesRuntimeEquipment: true,
            faceGenMeshPath: "meshes\\face.nif",
            faceGenTintPath: "textures\\face.dds",
            skips: []
        )
    }

    private let gore = [
        ResolvedBodyPart(
            origin: .outfit(FormID(0x300)), armature: FormID(0x301), modelPath: "neck.nif",
            firstPersonModelPath: nil, slots: [.decapitate]
        ),
        ResolvedBodyPart(
            origin: .outfit(FormID(0x300)), armature: FormID(0x302), modelPath: "headgore.nif",
            firstPersonModelPath: nil, slots: [.decapitatedHead]
        )
    ]

    @Test func eachPieceKeepsItsOwnSideOfTheLook() {
        let cut = visual(parts: [
            part(1, "cuirass.nif", [.body]),
            part(2, "helmet.nif", [.head, .hair]),
            part(3, "hood.nif", [.hair, .body])
        ]).decapitated(gore: gore)

        #expect(cut.body.parts.map(\.modelPath) == ["cuirass.nif", "hood.nif", "neck.nif"])
        #expect(cut.body.parts.map(\.cut) == [
            DismemberCut(side: .body, keepsUnpartitioned: true),
            DismemberCut(side: .body, keepsUnpartitioned: true),
            nil
        ])
        #expect(cut.body.attachments.count == 1, "the weapon stays in the hand")
        #expect(cut.body.headCut == DismemberCut(side: .body, keepsUnpartitioned: false))

        #expect(cut.head.parts.map(\.modelPath) == ["helmet.nif", "hood.nif", "headgore.nif"])
        #expect(cut.head.parts.map(\.cut) == [
            nil, DismemberCut(side: .head, keepsUnpartitioned: false), nil
        ])
        #expect(cut.head.attachments.isEmpty)
        #expect(cut.head.faceGenMeshPath == "meshes\\face.nif")
        #expect(cut.head.headCut == DismemberCut(side: .head, keepsUnpartitioned: true))
    }

    @Test func aRaceWithoutGoreStillSplits() {
        let cut = visual(parts: [part(1, "body.nif", [.body])]).decapitated(gore: [])
        #expect(cut.body.parts.map(\.modelPath) == ["body.nif"])
        #expect(cut.head.parts.isEmpty)
        #expect(cut.head.faceGenMeshPath != nil)
    }
}
