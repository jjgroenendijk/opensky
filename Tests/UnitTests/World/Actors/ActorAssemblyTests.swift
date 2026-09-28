// Actor assembly tests over synthetic ESM records + fake asset outcomes.
// No game bytes or GPU required. Visual fixtures cover deterministic gender,
// template source, outfit masking, FaceGen, and missing-asset policy.

import Foundation
@testable import opensky
import simd
import Testing

private struct FakeActorAssets: ActorAssetProvider {
    let failures: [String: ActorAssetFailure]

    init(failures: [String: ActorAssetFailure] = [:]) {
        self.failures = failures
    }

    func loadActorSkeleton(path: String) -> Result<String, ActorAssetFailure> {
        result(path)
    }

    func loadActorModel(
        path: String,
        skeleton _: String?
    ) -> Result<String, ActorAssetFailure> {
        result(path)
    }

    /// Attachments key on path plus bone, so a test can tell an attachment
    /// asset apart from the same model loaded as ordinary geometry.
    func loadActorAttachment(
        path: String,
        bone: String,
        skeleton _: String?
    ) -> Result<String, ActorAssetFailure> {
        failures[path].map(Result.failure) ?? .success("\(path)@\(bone)")
    }

    private func result(_ path: String) -> Result<String, ActorAssetFailure> {
        failures[path].map(Result.failure) ?? .success(path)
    }
}

struct ActorAssemblyTests {
    @Test func keepsGenderAndInheritedAppearanceSelection() throws {
        let inherited = FormID(0x2200)
        let source = appearance(female: true, headSource: inherited.rawValue)
        let visual = try makeResolver().resolve(appearance: source)
        let assembly = try ActorAssembler(provider: FakeActorAssets()).assemble(
            placed: placedActor(),
            visual: visual
        )

        #expect(assembly.isRenderable)
        #expect(assembly.visual.appearance.isFemale.value)
        #expect(assembly.visual.appearance.headParts.source == inherited)
        #expect(assembly.models.map(\.path) == [
            "torso_f.nif", "feet_f.nif",
            "meshes\\actors\\character\\facegendata\\facegeom\\skyrim.esm\\00002200.nif"
        ])
        #expect(assembly.models.last?.role == .faceGenHead(
            tintPath: "textures\\actors\\character\\facegendata\\facetint\\skyrim.esm\\00002200.dds"
        ))
    }

    @Test func preservesOutfitSlotMasking() throws {
        let visual = try makeResolver().resolve(appearance: appearance(outfit: 0x400))
        let assembly = try ActorAssembler(provider: FakeActorAssets()).assemble(
            placed: placedActor(),
            visual: visual
        )

        #expect(assembly.models.map(\.path).prefix(2) == ["clothes_m.nif", "feet_m.nif"])
        #expect(!assembly.models.contains { $0.path == "torso_m.nif" })
        #expect(assembly.skips.contains(ActorAssemblySkip(
            subject: .appearance(AppearanceSkip(
                subject: FormID(0x210), reason: .maskedByOutfit
            )),
            reason: .appearance
        )))
    }

    @Test func missingPartKeepsPartialActorRenderable() throws {
        let visual = try makeResolver().resolve(appearance: appearance(outfit: 0x400))
        let provider = FakeActorAssets(failures: [
            "clothes_m.nif": .missing,
            visual.faceGenMeshPath ?? "": .invalid
        ])
        let assembly = try ActorAssembler(provider: provider).assemble(
            placed: placedActor(),
            visual: visual
        )

        #expect(assembly.isRenderable)
        #expect(assembly.models.map(\.path) == ["feet_m.nif"])
        #expect(assembly.skips.contains { skip in
            skip.reason == .missingAsset && skip.subject == .model(
                role: .body(visual.parts[0]), path: "clothes_m.nif"
            )
        })
        #expect(assembly.skips.contains { $0.reason == .invalidAsset })
    }

    @Test func noBodyOrHeadIsReasonTaggedNonRenderable() throws {
        let visual = try makeResolver().resolve(appearance: appearance(headParts: []))
        var failures: [String: ActorAssetFailure] = Dictionary(
            uniqueKeysWithValues: visual.parts.map { ($0.modelPath, ActorAssetFailure.missing) }
        )
        if let face = visual.faceGenMeshPath {
            failures[face] = .missing
        }
        let assembly = try ActorAssembler(provider: FakeActorAssets(failures: failures)).assemble(
            placed: placedActor(),
            visual: visual
        )

        #expect(!assembly.isRenderable)
        #expect(assembly.models.isEmpty)
        #expect(assembly.skips.contains(ActorAssemblySkip(
            subject: .actor(FormID(0x9000)), reason: .noCoreGeometry
        )))
    }

    @Test func appliesACHRPositionRotationAndScale() throws {
        let position = SIMD3<Float>(100, -200, 30)
        let rotation = SIMD3<Float>(0.1, -0.2, 0.3)
        let scale: Float = 1.25
        let actor = try placedActor(position: position, rotation: rotation, scale: scale)
        let visual = try makeResolver(raceFaceGenHead: false)
            .resolve(appearance: appearance(headParts: []))
        let assembly = ActorAssembler(provider: FakeActorAssets()).assemble(
            placed: actor,
            visual: visual
        )
        let expected = MatrixMath.placement(
            position: position, rotation: rotation, scale: scale
        )

        for column in 0 ..< 4 {
            #expect(simd_distance(assembly.transform[column], expected[column]) < 1e-6)
        }
        #expect(assembly.transform.columns.3 == SIMD4(position, 1))
    }
}
