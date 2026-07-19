// ActorVisualResolver tests (milestone 5.2) over synthetic in-code records
// (ESMFixture) — never extracted game files (AGENTS.md "Legal & IP boundary").
// Chain shapes + FaceGen convention: docs/formats/actors.md.

import Foundation
@testable import opensky
import Testing

struct ActorVisualResolutionTests {
    /// FormIDs of the standard scenario (see makeResolver).
    private enum FID {
        static let npc: UInt32 = 0x1000
        static let race: UInt32 = 0x100
        static let foreignRace: UInt32 = 0x999
        static let skin: UInt32 = 0x200
        static let altSkin: UInt32 = 0x201
        static let skinTorso: UInt32 = 0x210
        static let skinFeet: UInt32 = 0x211
        static let skinForeign: UInt32 = 0x212
        static let clothes: UInt32 = 0x300
        static let clothesArma: UInt32 = 0x310
        static let robes: UInt32 = 0x320
        static let robesArma: UInt32 = 0x321
        static let outfit: UInt32 = 0x400
        static let leveledOutfit: UInt32 = 0x410
        static let bundleOutfit: UInt32 = 0x420
        static let leveledList: UInt32 = 0x500
        static let cyclicList: UInt32 = 0x510
        static let emptyList: UInt32 = 0x520
        static let bundleList: UInt32 = 0x530
    }

    // MARK: - Gender + skeleton

    @Test func malePicksMaleSkeletonAndModels() throws {
        let visual = try makeResolver().resolve(appearance: appearance())
        #expect(visual.skeletonPath == "skel_m.nif")
        #expect(visual.parts.map(\.modelPath) == ["torso_m.nif", "feet_m.nif"])
        #expect(visual.skin == FormID(FID.skin))
    }

    @Test func femalePicksFemaleSkeletonAndModels() throws {
        let visual = try makeResolver().resolve(appearance: appearance(female: true))
        #expect(visual.skeletonPath == "skel_f.nif")
        #expect(visual.parts.map(\.modelPath) == ["torso_f.nif", "feet_f.nif"])
    }

    @Test func missingSkeletonForGenderIsReasonTaggedSkip() throws {
        // Race with a male-only skeleton: female resolve degrades, male not.
        let resolver = makeResolver(femaleSkeleton: nil)
        let visual = try resolver.resolve(appearance: appearance(female: true))
        #expect(visual.skeletonPath == nil)
        #expect(visual.skips.contains(
            AppearanceSkip(subject: FormID(FID.race), reason: .noSkeletonForGender)
        ))
    }

    // MARK: - Skin fallback

    @Test func skinFallsBackToRaceDefaultWhenNPCHasNoWornArmor() throws {
        let visual = try makeResolver().resolve(appearance: appearance(wornArmor: nil))
        #expect(visual.skin == FormID(FID.skin))
    }

    @Test func npcWornArmorOverridesRaceSkin() throws {
        let visual = try makeResolver()
            .resolve(appearance: appearance(wornArmor: FID.altSkin))
        #expect(visual.skin == FormID(FID.altSkin))
        // Alt skin reuses the torso armature only — no feet part.
        #expect(visual.parts.map(\.modelPath) == ["torso_m.nif"])
    }

    @Test func missingSkinThrows() throws {
        let resolver = makeResolver(raceSkin: nil)
        #expect(throws: ActorVisualError.missingSkin(nil, npc: FormID(FID.npc))) {
            _ = try resolver.resolve(appearance: appearance(wornArmor: nil))
        }
    }

    @Test func danglingWornArmorThrows() throws {
        #expect(throws: ActorVisualError.missingSkin(
            FormID(0xDEAD), npc: FormID(FID.npc)
        )) {
            _ = try makeResolver().resolve(appearance: appearance(wornArmor: 0xDEAD))
        }
    }

    // MARK: - Race

    @Test func missingRaceThrows() throws {
        #expect(throws: ActorVisualError.missingRace(nil, npc: FormID(FID.npc))) {
            _ = try makeResolver().resolve(appearance: appearance(race: nil))
        }
        #expect(throws: ActorVisualError.missingRace(
            FormID(0xBEEF), npc: FormID(FID.npc)
        )) {
            _ = try makeResolver().resolve(appearance: appearance(race: 0xBEEF))
        }
    }

    // MARK: - Outfit chain + slot masking

    @Test func outfitPieceMasksCoveredSkinPart() throws {
        let visual = try makeResolver().resolve(appearance: appearance(outfit: FID.outfit))
        // Clothes cover the body slot: torso skin armature is masked, feet
        // stay naked. Outfit parts precede skin parts.
        #expect(visual.equippedSlots == [.body])
        #expect(visual.parts.map(\.modelPath) == ["clothes_m.nif", "feet_m.nif"])
        #expect(visual.parts.first?.origin == .outfit(FormID(FID.clothes)))
        #expect(visual.skips.contains(
            AppearanceSkip(subject: FormID(FID.skinTorso), reason: .maskedByOutfit)
        ))
    }

    @Test func outfitExpandsLeveledItemDeterministically() throws {
        let visual = try makeResolver()
            .resolve(appearance: appearance(outfit: FID.leveledOutfit))
        // LVLI holds clothes (level 1) + robes (level 5): highest level wins.
        #expect(visual.parts.map(\.modelPath) == ["robes_m.nif", "feet_m.nif"])
    }

    @Test func danglingOutfitThrows() throws {
        #expect(throws: ActorVisualError.brokenOutfitChain(
            outfit: FormID(0xFEED), item: nil, reason: .missingOutfitRecord
        )) {
            _ = try makeResolver().resolve(appearance: appearance(outfit: 0xFEED))
        }
    }

    @Test func danglingOutfitItemThrows() throws {
        let resolver = makeResolver(outfitItems: [0xACED])
        #expect(throws: ActorVisualError.brokenOutfitChain(
            outfit: FormID(FID.outfit), item: FormID(0xACED), reason: .danglingItem
        )) {
            _ = try resolver.resolve(appearance: appearance(outfit: FID.outfit))
        }
    }

    @Test func emptyLeveledItemListThrows() throws {
        let resolver = makeResolver(outfitItems: [FID.emptyList])
        #expect(throws: ActorVisualError.brokenOutfitChain(
            outfit: FormID(FID.outfit), item: FormID(FID.emptyList), reason: .emptyLeveledList
        )) {
            _ = try resolver.resolve(appearance: appearance(outfit: FID.outfit))
        }
    }

    @Test func cyclicLeveledItemListThrows() throws {
        let resolver = makeResolver(outfitItems: [FID.cyclicList])
        #expect(throws: ActorVisualError.brokenOutfitChain(
            outfit: FormID(FID.outfit), item: FormID(FID.cyclicList), reason: .leveledListCycle
        )) {
            _ = try resolver.resolve(appearance: appearance(outfit: FID.outfit))
        }
    }

    @Test func outfitUseAllListExpandsEveryEntry() throws {
        let visual = try makeResolver()
            .resolve(appearance: appearance(outfit: FID.bundleOutfit))
        // useAll LVLI is a bundle: clothes AND robes both equip.
        #expect(visual.parts.map(\.modelPath)
            == ["clothes_m.nif", "robes_m.nif", "feet_m.nif"])
    }

    // MARK: - Missing optional parts

    @Test func femaleFallsBackToMaleModelWhenFemaleMissing() throws {
        // Male-only feet armature (vanilla pattern, e.g. StormCloakBootsAA):
        // females reuse the male model instead of dropping the part.
        let resolver = makeResolver(feetFemaleModel: nil)
        let visual = try resolver.resolve(appearance: appearance(female: true))
        #expect(visual.parts.map(\.modelPath) == ["torso_f.nif", "feet_m.nif"])
        #expect(visual.skips.isEmpty)
    }

    @Test func armatureWithNoModelIsReasonTaggedSkip() throws {
        let resolver = makeResolver(feetMaleModel: nil, feetFemaleModel: nil)
        let visual = try resolver.resolve(appearance: appearance())
        #expect(visual.parts.map(\.modelPath) == ["torso_m.nif"])
        #expect(visual.skips.contains(
            AppearanceSkip(subject: FormID(FID.skinFeet), reason: .noModel)
        ))
    }

    @Test func armorWithNoCompatibleArmatureIsReasonTaggedSkip() throws {
        // Alt skin filtered to a foreign race only -> zero parts + skip.
        let resolver = makeResolver(altSkinArmatures: [FID.skinForeign])
        let visual = try resolver
            .resolve(appearance: appearance(wornArmor: FID.altSkin))
        #expect(visual.parts.isEmpty)
        #expect(visual.skips.contains(
            AppearanceSkip(subject: FormID(FID.altSkin), reason: .noCompatibleArmature)
        ))
    }

    @Test func danglingArmatureIsReasonTaggedSkip() throws {
        let resolver = makeResolver(altSkinArmatures: [0xF00D, FID.skinTorso])
        let visual = try resolver
            .resolve(appearance: appearance(wornArmor: FID.altSkin))
        #expect(visual.parts.map(\.modelPath) == ["torso_m.nif"])
        #expect(visual.skips.contains(
            AppearanceSkip(subject: FormID(0xF00D), reason: .danglingArmature)
        ))
    }

    // MARK: - FaceGen (cross-plugin identity)

    @Test func faceGenPathsUseDefiningPluginAndZeroPaddedObjectID() throws {
        // Head parts sourced from a master-owned record: master index 0 ->
        // Skyrim.esm, lowercased directory, 8-hex zero-padded objectFID.
        let visual = try makeResolver()
            .resolve(appearance: appearance(headSource: 0x0001_3BAC))
        #expect(visual.faceGenMeshPath
            == "meshes\\actors\\character\\facegendata\\facegeom\\skyrim.esm\\00013bac.nif")
        #expect(visual.faceGenTintPath
            == "textures\\actors\\character\\facegendata\\facetint\\skyrim.esm\\00013bac.dds")
    }

    @Test func faceGenZeroesLoadOrderByteForPluginOwnedRecords() throws {
        // Master index at/above the master count -> the plugin itself; the
        // load-order byte never leaks into the on-disk FaceGen key.
        let visual = try makeResolver()
            .resolve(appearance: appearance(headSource: 0x0100_0D62))
        #expect(visual.faceGenMeshPath
            == "meshes\\actors\\character\\facegendata\\facegeom\\follower.esp\\00000d62.nif")
    }

    @Test func faceGenNilForRaceWithoutFaceGenHeadFlag() throws {
        // Creature races (RACE DATA flag 0x2 clear) bake no FaceGen files.
        let visual = try makeResolver(raceFaceGenHead: false)
            .resolve(appearance: appearance())
        #expect(visual.faceGenMeshPath == nil)
        #expect(visual.faceGenTintPath == nil)
    }

    // MARK: - build(from:)

    @Test func buildIndexesAllFiveTopGroups() throws {
        var raceFields = ESMFixture.field("MNAM", Data())
        raceFields += ESMFixture.field("ANAM", ESMFixture.zstring("skel_m.nif"))
        var inam = Data()
        inam.appendUInt32(FID.clothes)
        var lvlo = Data()
        lvlo.appendUInt16(1)
        lvlo.appendUInt16(0)
        lvlo.appendUInt32(FID.clothes)
        lvlo.appendUInt32(1)
        let plugin = ESMFixture.tes4(masters: ["Skyrim.esm"])
            + ESMFixture.topGroup(
                "RACE",
                contents: ESMFixture.record("RACE", formID: FID.race, data: raceFields)
            )
            + ESMFixture.topGroup(
                "ARMO",
                contents: ESMFixture.record("ARMO", formID: FID.clothes, data: Data())
            )
            + ESMFixture.topGroup(
                "ARMA",
                contents: ESMFixture.record("ARMA", formID: FID.clothesArma, data: Data())
            )
            + ESMFixture.topGroup(
                "OTFT",
                contents: ESMFixture.record(
                    "OTFT", formID: FID.outfit, data: ESMFixture.field("INAM", inam)
                )
            )
            + ESMFixture.topGroup(
                "LVLI",
                contents: ESMFixture.record(
                    "LVLI", formID: FID.leveledList, data: ESMFixture.field("LVLO", lvlo)
                )
            )
        let file = try ESMFile(data: plugin)
        let resolver = ActorVisualResolver.build(
            from: file, localized: false, pluginName: "Follower.esp"
        )
        #expect(resolver.races[FID.race]?.maleSkeletonPath == "skel_m.nif")
        #expect(resolver.armors[FID.clothes] != nil)
        #expect(resolver.armorAddons[FID.clothesArma] != nil)
        #expect(resolver.outfits[FID.outfit]?.items == [FormID(FID.clothes)])
        #expect(resolver.leveledItems[FID.leveledList]?.entries.count == 1)
        #expect(resolver.formIDResolver.masters == ["Skyrim.esm"])
        #expect(resolver.formIDResolver.pluginName == "Follower.esp")
    }
}
