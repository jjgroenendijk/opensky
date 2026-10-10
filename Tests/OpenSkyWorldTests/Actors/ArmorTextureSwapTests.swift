// ARMA MO2S/MO3S alternate textures resolve through their TXST into per-shape
// textures, the same override a static's MODS gets.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
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
}
