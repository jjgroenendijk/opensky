// The wearer's skin texture on every part that shows skin. A race's naked-skin
// armatures name the texture set in `ARMA NAM0`/`NAM1`; armour does not, so a worn
// piece takes the set of the skin armature whose slots it shares. Source: the
// Creation Kit wiki, https://ck.uesp.net/wiki/ArmorAddon ("Skin Texture").

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh

nonisolated extension ActorVisualResolver {
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
                let setID = female
                ? armature.femaleSkinTexture ?? armature.maleSkinTexture
                : armature.maleSkinTexture ?? armature.femaleSkinTexture,
                let set = textureSets[setID.rawValue]
            else { return nil }
            let key = { (slot: Int) in
                set.paths.indices.contains(slot)
                    ? set.paths[slot].flatMap(NIFShaderTextureSet.vfsKey(for:)) : nil
            }
            return SkinArmature(
                armature: id,
                slots: armature.bodyTemplate?.slots ?? skin.bodyTemplate?.slots ?? BodySlots(),
                textures: ModelSurfaceOverride.SkinTextures(
                    diffuse: key(0), normal: key(1), lightMask: key(3), specular: key(7)
                )
            )
        }
    }
}
