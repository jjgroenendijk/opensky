// The player's race menu face in the scene: the head is assembled from parts,
// each part's chargen TRI carries the slider morphs, and the tint layers build
// the face tint the face part overlays. See docs/engine/race-menu.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyImageKernels
import OpenSkyRendering

nonisolated extension CellSceneBuilder {
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

    /// One morph buffer per skinned head part mesh whose part has a chargen TRI
    /// of the same vertex count, already set to the slider weights.
    func chargenMorphs(
        assembly: ActorAssembly<ActorRenderAsset>, appearance: PlayerAppearanceOverride
    ) -> [ObjectIdentifier: FaceMorphBuffer] {
        let weights = ChargenMorphs.weights(
            morphs: appearance.faceMorphs,
            parts: appearance.faceParts
        )
        guard !weights.isEmpty, let records = actorVisualResolver?.headParts, let fileSystem else {
            return [:]
        }
        var buffers: [ObjectIdentifier: FaceMorphBuffer] = [:]
        for model in assembly.models {
            guard
                case let .headPart(part) = model.role,
                let path = records[part.formID.rawValue]?.morphPaths
                    .first(where: { $0.kind == .chargen })?.path,
                case let .success(tri) = faceMorphFile(Self.meshKey(path), fileSystem: fileSystem)
            else { continue }
            for mesh in model.asset.model.meshes where mesh.isSkinned {
                guard
                    let buffer = try? FaceMorphBuffer(
                        device: meshes.device,
                        tri: tri,
                        mesh: mesh
                    )
                else {
                    Self.logger.info("chargen TRI \(path, privacy: .public) does not fit its mesh")
                    continue
                }
                buffer.update(weights: weights)
                buffers[ObjectIdentifier(mesh)] = buffer
            }
        }
        return buffers
    }

    /// The tint masks of the player's race and sex.
    func raceTintMasks(_ appearance: PlayerAppearanceOverride) -> [RaceTintMask] {
        let head = actorVisualResolver?.races[appearance.race.rawValue]?.details.headData
        return (appearance.isFemale ? head?.female : head?.male)?.tintMasks ?? []
    }

    private static func meshKey(_ path: String) -> String {
        path.lowercased().hasPrefix("meshes\\") ? path : "meshes\\\(path)"
    }

    /// A key named after the tint layers, so the same face reuses one upload.
    private func faceTintKey(_ appearance: PlayerAppearanceOverride) -> String? {
        guard actorVisualResolver != nil, let fileSystem else { return nil }
        let masks = raceTintMasks(appearance)
        let layers = appearance.tints.compactMap { tint -> (String, PlayerAppearanceTint)? in
            let mask = masks.first { $0.index == tint.maskIndex }
            return mask?.texturePath.flatMap(NIFShaderTextureSet.vfsKey(for:)).map { ($0, tint) }
        }
        guard !layers.isEmpty else { return nil }
        let identity = layers.map { "\($0.0)|\($0.1.color)|\($0.1.strength)" }
            .joined(separator: ";")
        let key = "textures/opensky/facetint/\(Self.fnv1a(identity)).dds"
        if faceTintTextures[key] == nil {
            do {
                faceTintTextures[key] = try Self.faceTint(layers: layers, fileSystem: fileSystem)
            } catch {
                Self.logger.warning(
                    "face tint: \(String(describing: error), privacy: .public)"
                )
                return nil
            }
        }
        if let dds = faceTintTextures[key] {
            meshes.textures.register(dds: dds, key: key, usage: .color)
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
                    rgba: mask.rgba, width: mask.width, height: mask.height,
                    toWidth: width, toHeight: height
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
