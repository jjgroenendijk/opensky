// ARMA MO2S/MO3S alternate textures resolve through their TXST into per-shape
// textures, the same override a static's MODS gets.

import Foundation
@testable import OpenSkyActorPresentation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyWorldTesting
import Testing

struct ArmorTextureSwapTests {
    private func resolver() throws -> ActorVisualResolver {
        let base = makeResolver()
        let set = try TextureSet(record: ESMFixture.record("TXST", formID: 0x60, fields: [
            ("TX00", ESMFixture.zstring("armor\\steel_d.dds")),
            ("TX01", ESMFixture.zstring("armor\\steel_n.dds"))
        ]))
        return ActorVisualResolver(
            races: base.races,
            armors: base.armors,
            armorAddons: base.armorAddons,
            outfits: base.outfits,
            leveledItems: base.leveledItems,
            formIDResolver: base.formIDResolver,
            textureSets: [0x60: set]
        )
    }

    @Test func aSwapWithAKnownTextureSetBecomesShapeTextures() throws {
        let swaps = try resolver().textureSwaps([
            ModelData.AlternateTexture(
                shapeName: "Cuirass",
                textureSet: FormID(0x60),
                shapeIndex: 0
            ),
            ModelData.AlternateTexture(shapeName: "Belt", textureSet: FormID(0x99), shapeIndex: 1)
        ])

        #expect(swaps.map(\.shapeName) == ["Cuirass"])
        #expect(swaps.first?.diffuseTexture == NIFShaderTextureSet
            .vfsKey(for: "armor\\steel_d.dds"))
        #expect(swaps.first?.normalTexture == NIFShaderTextureSet.vfsKey(for: "armor\\steel_n.dds"))
    }

    @Test func aPartWithoutSwapsKeepsItsOwnTextures() {
        let part = ResolvedBodyPart(
            origin: .outfit(FormID(0x300)), armature: FormID(0x310), modelPath: "a.nif",
            firstPersonModelPath: nil, slots: .body
        )
        #expect(part.surface == nil)
    }

    /// The skin armatures name their texture sets; worn pieces borrow by slot.
    @Test func everyPartTakesTheWearersSkinTextures() throws {
        let base = makeResolver()
        let sets = try [0x70, 0x71].map { id in
            try TextureSet(record: ESMFixture.record("TXST", formID: UInt32(id), fields: [
                ("TX00", ESMFixture.zstring("skin\\\(id)_d.dds")),
                ("TX03", ESMFixture.zstring("skin\\\(id)_sk.dds")),
                ("TX07", ESMFixture.zstring("skin\\\(id)_s.dds"))
            ]))
        }
        let resolver = ActorVisualResolver(
            races: base.races, armors: base.armors, armorAddons: base.armorAddons,
            outfits: base.outfits, leveledItems: base.leveledItems,
            formIDResolver: base.formIDResolver, equipment: base.equipment,
            textureSets: [0x70: sets[0], 0x71: sets[1]]
        )
        let visual = try resolver.resolve(
            appearance: appearance(female: true), equipped: [FormID(0x300), FormID(0x330)]
        )
        let diffuse = Dictionary(uniqueKeysWithValues: visual.parts.map {
            ($0.armature.rawValue, $0.skinTextures?.diffuse)
        })
        #expect(diffuse[0x310] == NIFShaderTextureSet.vfsKey(for: "skin\\112_d.dds"))
        #expect(diffuse[0x331] == NIFShaderTextureSet.vfsKey(for: "skin\\112_d.dds"))
        #expect(diffuse[0x211] == NIFShaderTextureSet.vfsKey(for: "skin\\113_d.dds"))
        let feet = visual.parts.first { $0.armature.rawValue == 0x211 }?.skinTextures
        #expect(feet?.lightMask == NIFShaderTextureSet.vfsKey(for: "skin\\113_sk.dds"))
        #expect(feet?.specular == NIFShaderTextureSet.vfsKey(for: "skin\\113_s.dds"))
        #expect(feet?.normal == nil)
    }
}
