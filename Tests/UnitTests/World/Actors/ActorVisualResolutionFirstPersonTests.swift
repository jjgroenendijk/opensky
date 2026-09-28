// The first-person projection of a resolved actor visual, and the ARMA
// MOD4/MOD5 decode behind it (issue #190). Synthetic fixtures throughout.

@testable import opensky
import Testing

struct ArmorAddonFirstPersonModelTests {
    private func addon(
        maleFirstPerson: String?,
        femaleFirstPerson: String?
    ) throws -> ArmorAddon {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("FirstPersonAA"))
        fields += ESMFixture.field("MOD2", ESMFixture.zstring("armor\\m.nif"))
        fields += ESMFixture.field("MOD3", ESMFixture.zstring("armor\\f.nif"))
        if let maleFirstPerson {
            fields += ESMFixture.field("MOD4", ESMFixture.zstring(maleFirstPerson))
        }
        if let femaleFirstPerson {
            fields += ESMFixture.field("MOD5", ESMFixture.zstring(femaleFirstPerson))
        }
        return try ArmorAddon(
            record: InventoryFixture.record(
                ESMFixture.record("ARMA", formID: 0x7000, data: fields)
            )
        )
    }

    @Test func decodesBothFirstPersonModels() throws {
        let armature = try addon(
            maleFirstPerson: "armor\\1stm.nif", femaleFirstPerson: "armor\\1stf.nif"
        )
        #expect(armature.maleFirstPersonModelPath == "armor\\1stm.nif")
        #expect(armature.femaleFirstPersonModelPath == "armor\\1stf.nif")
        #expect(armature.firstPersonModelPath(female: false) == "armor\\1stm.nif")
        #expect(armature.firstPersonModelPath(female: true) == "armor\\1stf.nif")
        // The third-person models are untouched by the new fields.
        #expect(armature.maleModelPath == "armor\\m.nif")
        #expect(armature.femaleModelPath == "armor\\f.nif")
    }

    /// The same cross-gender fallback the third-person selection uses: an
    /// armature declaring only MOD4 shows it on both genders rather than
    /// showing nothing on one of them.
    @Test func fallsBackAcrossGenders() throws {
        let maleOnly = try addon(maleFirstPerson: "armor\\1stm.nif", femaleFirstPerson: nil)
        #expect(maleOnly.firstPersonModelPath(female: true) == "armor\\1stm.nif")
        let femaleOnly = try addon(maleFirstPerson: nil, femaleFirstPerson: "armor\\1stf.nif")
        #expect(femaleOnly.firstPersonModelPath(female: false) == "armor\\1stf.nif")
    }

    /// An armature with neither answers nil, which is the projection's signal
    /// that the piece is not visible from the eye.
    @Test func absentFirstPersonModelsReadAsNil() throws {
        let bare = try addon(maleFirstPerson: nil, femaleFirstPerson: nil)
        #expect(bare.maleFirstPersonModelPath == nil)
        #expect(bare.femaleFirstPersonModelPath == nil)
        #expect(bare.firstPersonModelPath(female: false) == nil)
        #expect(bare.firstPersonModelPath(female: true) == nil)
    }
}

struct ActorVisualResolutionFirstPersonTests {
    private static let rigPath = "meshes\\actors\\character\\_1stperson\\skeleton.nif"

    private func part(
        armature: UInt32,
        model: String,
        firstPerson: String?
    ) -> ResolvedBodyPart {
        ResolvedBodyPart(
            origin: .outfit(FormID(0x100)),
            armature: FormID(armature),
            modelPath: model,
            firstPersonModelPath: firstPerson,
            slots: [.body]
        )
    }

    private func visual(parts: [ResolvedBodyPart]) -> ResolvedActorVisual {
        ResolvedActorVisual(
            appearance: appearance(),
            skeletonPath: "actors\\character\\character assets\\skeleton.nif",
            skin: FormID(0x200),
            equippedSlots: [.body],
            parts: parts,
            attachments: [ResolvedAttachment(
                item: FormID(0x300), modelPath: "weapons\\sword.nif", bone: "Weapon"
            )],
            usesRuntimeEquipment: true,
            faceGenMeshPath: "meshes\\face.nif",
            faceGenTintPath: "textures\\face.dds",
            skips: []
        )
    }

    @Test func swapsEveryPartOntoItsFirstPersonModel() {
        let projected = visual(parts: [
            part(armature: 1, model: "armor\\torso.nif", firstPerson: "armor\\1sttorso.nif"),
            part(armature: 2, model: "armor\\hands.nif", firstPerson: "armor\\1sthands.nif")
        ]).firstPersonProjection(skeletonPath: Self.rigPath)

        #expect(projected.parts.map(\.modelPath) == [
            "armor\\1sttorso.nif", "armor\\1sthands.nif"
        ])
        #expect(projected.skeletonPath == Self.rigPath)
        #expect(projected.parts.map(\.armature) == [FormID(1), FormID(2)])
        #expect(projected.skips.isEmpty)
    }

    /// The flagged assumption, pinned: a piece with no MOD4/MOD5 is dropped and
    /// says so, rather than falling back to its third-person mesh.
    @Test func dropsPiecesWithNoFirstPersonModel() {
        let projected = visual(parts: [
            part(armature: 1, model: "armor\\torso.nif", firstPerson: "armor\\1sttorso.nif"),
            part(armature: 2, model: "armor\\helmet.nif", firstPerson: nil)
        ]).firstPersonProjection(skeletonPath: Self.rigPath)

        #expect(projected.parts.map(\.modelPath) == ["armor\\1sttorso.nif"])
        #expect(projected.skips == [
            AppearanceSkip(subject: FormID(2), reason: .noFirstPersonModel)
        ])
    }

    /// The M12 attachment carries across untouched — the bone is spelled the
    /// same in both rigs — and the FaceGen head does not, because the eye is
    /// inside it.
    @Test func keepsAttachmentsAndDropsTheHead() {
        let projected = visual(parts: [
            part(armature: 1, model: "armor\\torso.nif", firstPerson: "armor\\1sttorso.nif")
        ]).firstPersonProjection(skeletonPath: Self.rigPath)

        #expect(projected.attachments.map(\.bone) == ["Weapon"])
        #expect(projected.attachments.map(\.modelPath) == ["weapons\\sword.nif"])
        #expect(projected.faceGenMeshPath == nil)
        #expect(projected.faceGenTintPath == nil)
    }

    /// The projection is of one resolve, so the equipped set and the slot mask
    /// it produced are the same values in both rigs. That is what makes an
    /// equip change reach the arms without a second resolution chain.
    @Test func carriesTheEquippedStateThrough() {
        let source = visual(parts: [
            part(armature: 1, model: "armor\\torso.nif", firstPerson: "armor\\1sttorso.nif")
        ])
        let projected = source.firstPersonProjection(skeletonPath: Self.rigPath)
        #expect(projected.equippedSlots == source.equippedSlots)
        #expect(projected.usesRuntimeEquipment == source.usesRuntimeEquipment)
        #expect(projected.skin == source.skin)
        #expect(projected.appearance == source.appearance)
    }

    /// Skips the third-person resolve already recorded are kept rather than
    /// replaced, so a dangling armature stays reported in both rigs.
    @Test func preservesUpstreamSkips() {
        var source = visual(parts: [])
        source = ResolvedActorVisual(
            appearance: source.appearance,
            skeletonPath: source.skeletonPath,
            skin: source.skin,
            equippedSlots: source.equippedSlots,
            parts: [part(armature: 9, model: "a.nif", firstPerson: nil)],
            attachments: source.attachments,
            usesRuntimeEquipment: source.usesRuntimeEquipment,
            faceGenMeshPath: source.faceGenMeshPath,
            faceGenTintPath: source.faceGenTintPath,
            skips: [AppearanceSkip(subject: FormID(5), reason: .danglingArmature)]
        )
        let projected = source.firstPersonProjection(skeletonPath: Self.rigPath)
        #expect(projected.skips == [
            AppearanceSkip(subject: FormID(5), reason: .danglingArmature),
            AppearanceSkip(subject: FormID(9), reason: .noFirstPersonModel)
        ])
    }
}
