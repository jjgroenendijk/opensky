// Runtime equipment in visual resolution and assembly (issue #178, roadmap
// item 12.2.1): the equipped-set override of the plugin default outfit, ARMA
// DNAM draw ordering, and the weapon hand attachment.
//
// Synthetic ARMO/ARMA/NPC_ fixtures throughout (ActorVisualFixtures.swift) —
// no extracted game records.

import Foundation
@testable import opensky
import simd
import Testing

/// Records every attachment load, so a test can assert on the bone as well as
/// on the path.
private struct RecordingAssets: ActorAssetProvider {
    final class Log: @unchecked Sendable {
        var attachments: [(path: String, bone: String)] = []
    }

    let log = Log()
    var failures: [String: ActorAssetFailure] = [:]

    func loadActorSkeleton(path: String) -> Result<String, ActorAssetFailure> {
        failures[path].map(Result.failure) ?? .success(path)
    }

    func loadActorModel(
        path: String,
        skeleton _: String?
    ) -> Result<String, ActorAssetFailure> {
        failures[path].map(Result.failure) ?? .success(path)
    }

    func loadActorAttachment(
        path: String,
        bone: String,
        skeleton _: String?
    ) -> Result<String, ActorAssetFailure> {
        log.attachments.append((path, bone))
        return failures[path].map(Result.failure) ?? .success("\(path)@\(bone)")
    }
}

struct ActorEquipmentResolutionTests {
    // MARK: - Equipped-set override

    @Test func noEquippedSetLeavesThePluginOutfitPathUntouched() throws {
        let visual = try makeResolver().resolve(appearance: appearance(outfit: 0x400))

        #expect(!visual.usesRuntimeEquipment)
        #expect(visual.attachments.isEmpty)
        #expect(visual.parts.map(\.modelPath) == ["clothes_m.nif", "feet_m.nif"])
    }

    /// The equipped set replaces the outfit wholesale. Here the actor's DOFT
    /// still names the clothes, and the runtime set names the robes only, so
    /// the robes render and the clothes do not.
    @Test func equippedSetOverridesTheDefaultOutfit() throws {
        let visual = try makeResolver().resolve(
            appearance: appearance(outfit: 0x400), equipped: [FormID(0x320)]
        )

        #expect(visual.usesRuntimeEquipment)
        #expect(visual.parts.map(\.modelPath) == ["robes_m.nif", "feet_m.nif"])
    }

    /// The torso stays masked because the equipped robes claim slot 32 — the
    /// same masking machinery, driven from runtime state instead of DOFT.
    @Test func equippedSetStillMasksCoveredSkin() throws {
        let visual = try makeResolver().resolve(
            appearance: appearance(outfit: 0x400), equipped: [FormID(0x320)]
        )

        #expect(visual.equippedSlots == BodySlots(rawValue: 0b0100))
        #expect(visual.skips.contains(
            AppearanceSkip(subject: FormID(0x210), reason: .maskedByOutfit)
        ))
        #expect(!visual.parts.contains { $0.modelPath == "torso_m.nif" })
    }

    /// An empty equipped set is not "no equipment" — it is a stripped actor,
    /// and the skin that the outfit was hiding comes back.
    @Test func emptyEquippedSetUndressesTheActor() throws {
        let visual = try makeResolver().resolve(
            appearance: appearance(outfit: 0x400), equipped: []
        )

        #expect(visual.usesRuntimeEquipment)
        #expect(visual.equippedSlots.isEmpty)
        #expect(visual.parts.map(\.modelPath) == ["torso_m.nif", "feet_m.nif"])
    }

    @Test func equippingTwoPiecesRendersBoth() throws {
        let visual = try makeResolver().resolve(
            appearance: appearance(), equipped: [FormID(0x320), FormID(0x330)]
        )

        #expect(visual.parts.map(\.modelPath)
            == ["robes_m.nif", "gloves_m.nif", "feet_m.nif"])
    }

    /// A runtime equipped set is ordinary runtime state, so an unusable entry
    /// degrades to a reason-tagged skip. A broken DOFT chain still throws —
    /// that is malformed plugin data and the milestone gate says so.
    @Test func unrenderableEquippedItemIsAReasonTaggedSkipNotAThrow() throws {
        let visual = try makeResolver().resolve(
            appearance: appearance(), equipped: [FormID(0x700), FormID(0x320)]
        )

        #expect(visual.skips.contains(
            AppearanceSkip(subject: FormID(0x700), reason: .unrenderableEquipment)
        ))
        #expect(visual.parts.map(\.modelPath) == ["robes_m.nif", "feet_m.nif"])
    }

    @Test func brokenDefaultOutfitStillThrows() {
        #expect(throws: ActorVisualError.self) {
            try makeResolver().resolve(appearance: appearance(outfit: 0x9999))
        }
    }

    // MARK: - ARMA DNAM draw order

    /// Priority orders parts; it never removes them. Confirmed against the
    /// install: `OrcishCuirassAA` is priority 5 over body|forearms|calves and
    /// `OrcishBootsAA` is priority 10 over feet|calves, and vanilla draws both
    /// — hiding the loser would delete the cuirass's torso.
    @Test func higherPriorityArmatureSortsLastAndNothingIsDropped() throws {
        let resolver = makeResolver(clothesPriority: 5, robesPriority: 10)
        let visual = try resolver.resolve(
            appearance: appearance(), equipped: [FormID(0x300), FormID(0x320)]
        )

        #expect(visual.parts.map(\.modelPath) == ["clothes_m.nif", "robes_m.nif", "feet_m.nif"])
        #expect(!visual.skips.contains { $0.reason == .noModel })
    }

    @Test func reversedPrioritiesReverseTheDrawOrder() throws {
        let resolver = makeResolver(clothesPriority: 10, robesPriority: 5)
        let visual = try resolver.resolve(
            appearance: appearance(), equipped: [FormID(0x300), FormID(0x320)]
        )

        #expect(visual.parts.map(\.modelPath) == ["robes_m.nif", "clothes_m.nif", "feet_m.nif"])
    }

    /// Equal priorities — which is every DNAM-less fixture and most vanilla
    /// outfits — leave the resolution order exactly as it was, so nothing
    /// about the existing plugin-outfit path moves.
    @Test func equalPrioritiesPreserveResolutionOrder() throws {
        let visual = try makeResolver().resolve(
            appearance: appearance(), equipped: [FormID(0x300), FormID(0x320)]
        )

        #expect(visual.parts.map(\.modelPath) == ["clothes_m.nif", "robes_m.nif", "feet_m.nif"])
    }

    @Test func skinIsNotSortedAmongTheWornParts() throws {
        // Feet skin has priority 0 and would sort first if it took part.
        let resolver = makeResolver(clothesPriority: 5)
        let visual = try resolver.resolve(appearance: appearance(), equipped: [FormID(0x300)])

        #expect(visual.parts.map(\.modelPath) == ["clothes_m.nif", "feet_m.nif"])
    }

    // MARK: - Attachments

    @Test func equippedWeaponResolvesToAHandAttachment() throws {
        let visual = try makeResolver().resolve(
            appearance: appearance(), equipped: [FormID(0x600)]
        )

        #expect(visual.attachments == [ResolvedAttachment(
            item: FormID(0x600), modelPath: "sword.nif", bone: "Weapon"
        )])
        // A weapon is not a body part and contributes no biped slots.
        #expect(visual.equippedSlots.isEmpty)
        #expect(visual.parts.map(\.modelPath) == ["torso_m.nif", "feet_m.nif"])
    }

    @Test func weaponWithNoModelIsAReasonTaggedSkip() throws {
        let base = makeResolver()
        let resolver = ActorVisualResolver(
            races: base.races,
            armors: base.armors,
            armorAddons: base.armorAddons,
            outfits: base.outfits,
            leveledItems: base.leveledItems,
            formIDResolver: base.formIDResolver,
            equipment: makeEquipmentCatalog(swordModel: nil)
        )
        let visual = try resolver.resolve(appearance: appearance(), equipped: [FormID(0x600)])

        #expect(visual.attachments.isEmpty)
        #expect(visual.skips.contains(
            AppearanceSkip(subject: FormID(0x600), reason: .unrenderableEquipment)
        ))
    }
}

struct ActorEquipmentAssemblyTests {
    /// FaceGen is off in this suite: a baked head model is one more path in
    /// every assertion and none of these tests are about it.
    private func resolver(clothesPriority: UInt8 = 0) -> ActorVisualResolver {
        makeResolver(raceFaceGenHead: false, clothesPriority: clothesPriority)
    }

    @Test func attachmentLoadsThroughTheAttachmentPathWithItsBone() throws {
        let visual = try resolver().resolve(
            appearance: appearance(), equipped: [FormID(0x600)]
        )
        let provider = RecordingAssets()
        let assembly = try ActorAssembler(provider: provider).assemble(
            placed: placedActor(), visual: visual
        )

        #expect(provider.log.attachments.map(\.path) == ["sword.nif"])
        #expect(provider.log.attachments.map(\.bone) == ["Weapon"])
        #expect(assembly.models.last?.role == .attachment(ResolvedAttachment(
            item: FormID(0x600), modelPath: "sword.nif", bone: "Weapon"
        )))
    }

    /// An equip changes the assembled model set — the acceptance rule, proved
    /// through `ActorAssembler` rather than at the resolver alone.
    @Test func equipChangesTheAssembledModels() throws {
        let resolver = resolver()
        let before = try resolver.resolve(appearance: appearance(outfit: 0x400))
        let after = try resolver.resolve(
            appearance: appearance(outfit: 0x400),
            equipped: [FormID(0x320), FormID(0x600)]
        )
        let assembler = ActorAssembler(provider: RecordingAssets())

        let beforeModels = try assembler.assemble(placed: placedActor(), visual: before).models
        let afterModels = try assembler.assemble(placed: placedActor(), visual: after).models

        #expect(beforeModels.map(\.path) == ["clothes_m.nif", "feet_m.nif"])
        #expect(afterModels.map(\.path) == ["robes_m.nif", "feet_m.nif", "sword.nif"])
    }

    /// A missing weapon model does not cost the actor its body: the
    /// attachment is a reason-tagged skip and everything else still renders.
    @Test func failedAttachmentLeavesTheActorRenderable() throws {
        let visual = try resolver().resolve(
            appearance: appearance(), equipped: [FormID(0x600)]
        )
        var provider = RecordingAssets()
        provider.failures = ["sword.nif": .missing]
        let assembly = try ActorAssembler(provider: provider).assemble(
            placed: placedActor(), visual: visual
        )

        #expect(assembly.isRenderable)
        #expect(assembly.models.map(\.path) == ["torso_m.nif", "feet_m.nif"])
        #expect(assembly.skips.contains {
            $0.reason == .missingAsset
                && $0.subject == .model(
                    role: .attachment(ResolvedAttachment(
                        item: FormID(0x600), modelPath: "sword.nif", bone: "Weapon"
                    )),
                    path: "sword.nif"
                )
        })
    }

    /// A weapon alone is not core geometry. An actor whose body failed to load
    /// stays rejected rather than becoming a sword floating over nothing.
    @Test func attachmentAloneIsNotCoreGeometry() throws {
        let visual = try resolver().resolve(
            appearance: appearance(headParts: []), equipped: [FormID(0x600)]
        )
        var provider = RecordingAssets()
        provider.failures = ["torso_m.nif": .missing, "feet_m.nif": .missing]
        let assembly = try ActorAssembler(provider: provider).assemble(
            placed: placedActor(), visual: visual
        )

        #expect(!assembly.isRenderable)
        #expect(assembly.models.isEmpty)
        #expect(provider.log.attachments.isEmpty)
        #expect(assembly.skips.contains { $0.reason == .noCoreGeometry })
    }
}
