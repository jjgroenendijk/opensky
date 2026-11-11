// The player's race menu face in the scene: the head is assembled from parts,
// each part's chargen TRI carries the slider morphs, and the tint layers build
// the face tint the face part overlays. See docs/engine/race-menu.md.

import Foundation
import OpenSkyActorPresentation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyImageKernels
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyRuntimeState
import OpenSkyWorldInterface

nonisolated extension CellActorBuilder {
    /// Assembles the head from parts and gives the face part a face tint built from
    /// the tint layers. A race without head parts keeps the baked head.
    func chargenVisual(
        _ visual: ResolvedActorVisual, appearance: PlayerAppearanceOverride
    ) -> ResolvedActorVisual {
        guard !visual.headParts.parts.isEmpty else { return visual }
        var visual = visual
        visual.headSource = .assembled
        guard !appearance.tints.isEmpty, let key = faceTintKey(appearance) else { return visual }
        let parts = visual.headParts.parts.map { part -> ResolvedHeadPart in
            guard part.partType == .face else { return part }
            var part = part
            part.faceTintTexture = key
            return part
        }
        visual.headParts = HeadPartSet(parts: parts, misses: visual.headParts.misses)
        return visual
    }

    /// The tint masks of the player's race and sex.
    func raceTintMasks(_ appearance: PlayerAppearanceOverride) -> [RaceTintMask] {
        let head = owner.actorVisualResolver?.races[appearance.race.rawValue]?.details.headData
        return (appearance.isFemale ? head?.female : head?.male)?.tintMasks ?? []
    }

    /// A key named after the tint layers, so the same face reuses one upload.
    private func faceTintKey(_ appearance: PlayerAppearanceOverride) -> String? {
        guard
            owner.actorVisualResolver != nil,
            let fileSystem = owner.fileSystem else { return nil }
        let masks = raceTintMasks(appearance)
        let layers = appearance.tints.compactMap { tint -> (String, PlayerAppearanceTint)? in
            let mask = masks.first { $0.index == tint.maskIndex }
            return mask?.texturePath.flatMap(NIFShaderTextureSet.vfsKey(for:)).map { ($0, tint) }
        }
        guard !layers.isEmpty else { return nil }
        let identity = layers.map { "\($0.0)|\($0.1.color)|\($0.1.strength)" }
            .joined(separator: ";")
        let key = "textures/opensky/facetint/\(Self.fnv1a(identity)).dds"
        if owner.faceTintTextures[key] == nil {
            do {
                owner.faceTintTextures[key] = try Self.faceTint(
                    layers: layers,
                    fileSystem: fileSystem
                )
            } catch {
                CellSceneBuilder.logger.warning(
                    "face tint: \(String(describing: error), privacy: .public)"
                )
                return nil
            }
        }
        if let dds = owner.faceTintTextures[key] {
            owner.meshes.textures.register(dds: dds, key: key, usage: .color)
        }
        return key
    }

    /// The layers composed at the first mask's size, as the game bakes an NPC's
    /// `facetint` texture.
    private static func faceTint(
        layers: [(String, PlayerAppearanceTint)], fileSystem: any GameFileSource
    ) throws -> Data {
        let images = try layers.map { path, _ in
            try DDSDecoder.topLevel(fileSystem.contents(forPath: path))
        }
        let width = images.first?.width ?? 0
        let height = images.first?.height ?? 0
        let painted = zip(images, layers).map { mask, layer in
            ChargenTintLayer(
                mask: ChargenTints.coverage(
                    rgba: mask.rgba, size: (mask.width, mask.height), to: (width, height)
                ),
                color: layer.1.color, strength: layer.1.strength
            )
        }
        let rgba = ChargenTints.compose(width: width, height: height, layers: painted)
        return DDSEncoder.rgba8888(DecodedImage(width: width, height: height, rgba: rgba))
    }

    private static func fnv1a(_ text: String) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }
}
