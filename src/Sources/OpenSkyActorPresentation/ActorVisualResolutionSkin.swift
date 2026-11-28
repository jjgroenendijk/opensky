// The wearer's skin texture on every part that shows skin. A race's naked-skin
// armatures name the texture set in `ARMA NAM0`/`NAM1`; armour does not, so a worn
// piece takes the set of the skin armature whose slots it shares. Source: the
// Creation Kit wiki, https://ck.uesp.net/wiki/ArmorAddon ("Skin Texture").

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyWorldInterface

/// The part of `ActorVisualResolver` that reads skin and texture swaps from ARMA and
/// TXST records.
nonisolated struct ActorSkinTextureReads: Sendable {
    /// An entry of a skin swap list is `trunc(weight * swapListScale * count)`.
    static let swapListScale: Float = 0.0099

    let armorAddons: [UInt32: ArmorAddon]
    let textureSets: [UInt32: TextureSet]
    let formLists: [UInt32: FormList]
    let weight: Float

    private struct SkinArmature {
        let armature: FormID
        let slots: BodySlots
        let textures: ModelSurfaceOverride.SkinTextures
    }

    /// `parts` with the skin textures of `skin` for `race`. A part that shares no
    /// slot with a skin armature takes the body's set.
    func withSkinTextures(
        _ parts: [ResolvedBodyPart], skin: Armor, race: FormID, female: Bool
    ) -> [ResolvedBodyPart] {
        let skins = skinArmatures(of: skin, race: race, female: female)
        guard !skins.isEmpty else { return parts }
        let body = skins.first { $0.slots.overlaps(.body) } ?? skins[0]
        return parts.map { part in
            let match = skins.first { $0.armature == part.armature }
                ?? skins.first { $0.slots.overlaps(part.slots) }
                ?? body
            var part = part
            part.skinTextures = match.textures
            return part
        }
    }

    private func skinArmatures(of skin: Armor, race: FormID, female: Bool) -> [SkinArmature] {
        skin.armatures.compactMap { id in
            guard
                let armature = armorAddons[id.rawValue],
                armature.primaryRace == race || armature.additionalRaces.contains(race),
                let textures = ownSkinTextures(of: id, female: female)
            else { return nil }
            return SkinArmature(
                armature: id,
                slots: armature.bodyTemplate?.slots ?? skin.bodyTemplate?.slots ?? BodySlots(),
                textures: textures
            )
        }
    }

    /// The armature's own skin texture set, or nil when it names none: the entry of its
    /// swap list (`NAM2`/`NAM3`) the wearer's weight picks, else `NAM0`/`NAM1`
    /// (docs/formats/armor.md#skin-texture).
    func ownSkinTextures(
        of armatureID: FormID, female: Bool
    ) -> ModelSurfaceOverride.SkinTextures? {
        guard
            let armature = armorAddons[armatureID.rawValue],
            let setID = swapListEntry(of: armature, female: female) ?? (female
                ? armature.femaleSkinTexture ?? armature.maleSkinTexture
                : armature.maleSkinTexture ?? armature.femaleSkinTexture),
            let set = textureSets[setID.rawValue]
        else { return nil }
        let key = { (slot: Int) in
            set.paths.indices.contains(slot)
                ? set.paths[slot].flatMap(NIFShaderTextureSet.vfsKey(for:)) : nil
        }
        return ModelSurfaceOverride.SkinTextures(
            diffuse: key(0), normal: key(1), lightMask: key(3), specular: key(7)
        )
    }

    /// A female wearer reads the male list when hers is empty. A list of one entry swaps
    /// nothing: vanilla female Argonians keep their own scales over a human body list.
    func swapListEntry(of armature: ArmorAddon, female: Bool) -> FormID? {
        let listID = female
            ? armature.femaleSkinTextureSwapList ?? armature.maleSkinTextureSwapList
            : armature.maleSkinTextureSwapList
        guard let listID, let entries = formLists[listID.rawValue]?.entries, entries.count > 1
        else { return nil }
        let scaled = min(max(weight, 0), 100) * Self.swapListScale * Float(entries.count)
        return entries[min(Int(scaled), entries.count - 1)]
    }

    /// The swaps of the model `female` wears, with the same cross-gender
    /// fallback as the model path.
    func textureSwaps(
        of armature: ArmorAddon, female: Bool
    ) -> [ModelSurfaceOverride.ShapeTextures] {
        let model = (female ? armature.femaleModel : armature.maleModel)
            ?? armature.maleModel ?? armature.femaleModel
        return textureSwaps(model?.alternateTextures ?? [])
    }

    /// ARMA alternate textures as per-shape textures. An entry whose TXST is
    /// missing keeps the shape's own textures, as `MODS` does on a static.
    func textureSwaps(
        _ alternates: [ModelData.AlternateTexture]
    ) -> [ModelSurfaceOverride.ShapeTextures] {
        alternates.compactMap { alternate in
            textureSets[alternate.textureSet.rawValue].map { set in
                ModelSurfaceOverride.ShapeTextures(
                    shapeName: alternate.shapeName,
                    diffuseTexture: set.diffusePath.flatMap(NIFShaderTextureSet.vfsKey(for:)),
                    normalTexture: set.normalPath.flatMap(NIFShaderTextureSet.vfsKey(for:))
                )
            }
        }
    }
}
