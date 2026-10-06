// The player's race menu face in the scene: the head is assembled from parts,
// each part's chargen TRI carries the slider morphs, and the face part's color
// map is painted with the tint layers. See docs/engine/race-menu.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyRendering

nonisolated extension CellSceneBuilder {
    /// Assembles the head from parts and swaps the face part's color map for the
    /// painted one. A race without head parts keeps the baked head.
    func chargenVisual(
        _ visual: ResolvedActorVisual, appearance: PlayerAppearanceOverride
    ) -> ResolvedActorVisual {
        guard !visual.headParts.parts.isEmpty else { return visual }
        var visual = visual
        visual.headSource = .assembled
        guard !appearance.tints.isEmpty else { return visual }
        let parts = visual.headParts.parts.map { part -> ResolvedHeadPart in
            guard
                part.partType == .face,
                let base = part.diffuseTexture.flatMap(NIFShaderTextureSet.vfsKey(for:)),
                let key = paintedFaceKey(base: base, appearance: appearance)
            else { return part }
            return ResolvedHeadPart(
                formID: part.formID, editorID: part.editorID, partType: part.partType,
                origin: part.origin, modelPath: part.modelPath, diffuseTexture: key,
                normalTexture: part.normalTexture, tint: part.tint
            )
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

    private static func meshKey(_ path: String) -> String {
        path.lowercased().hasPrefix("meshes\\") ? path : "meshes\\\(path)"
    }

    /// A key named after the face's inputs, so the same face reuses one upload.
    private func paintedFaceKey(base: String, appearance: PlayerAppearanceOverride) -> String? {
        guard let resolver = actorVisualResolver, let fileSystem else { return nil }
        let head = resolver.races[appearance.race.rawValue]?.details.headData
        let masks = (appearance.isFemale ? head?.female : head?.male)?.tintMasks ?? []
        let layers = appearance.tints.compactMap { tint -> (String, PlayerAppearanceTint)? in
            let mask = masks.first { $0.index == tint.maskIndex }
            return mask?.texturePath.flatMap(NIFShaderTextureSet.vfsKey(for:)).map { ($0, tint) }
        }
        let identity = ([base] + layers.map { "\($0.0)|\($0.1.color)|\($0.1.strength)" })
            .joined(separator: ";")
        let key = "textures/opensky/facetint/\(Self.fnv1a(identity)).dds"
        if faceTintTextures[key] == nil {
            do {
                faceTintTextures[key] = try Self.paintFace(
                    base: base, layers: layers, fileSystem: fileSystem
                )
            } catch {
                Self.logger
                    .warning(
                        """
                        face tint for \(base, privacy: .public): \
                        \(String(describing: error), privacy: .public)
                        """
                    )
                return nil
            }
        }
        if let dds = faceTintTextures[key] {
            meshes.textures.register(dds: dds, key: key, usage: .color)
        }
        return key
    }

    private static func paintFace(
        base: String, layers: [(String, PlayerAppearanceTint)], fileSystem: any GameFileSource
    ) throws -> Data {
        var face = try DDSDecoder.topLevel(fileSystem.contents(forPath: base))
        let painted = try layers.map { path, tint in
            let mask = try DDSDecoder.topLevel(fileSystem.contents(forPath: path))
            return ChargenTintLayer(
                mask: ChargenTints.coverage(
                    rgba: mask.rgba, width: mask.width, height: mask.height,
                    toWidth: face.width, toHeight: face.height
                ),
                color: tint.color, strength: tint.strength
            )
        }
        face.rgba = ChargenTints.paint(rgba: face.rgba, layers: painted)
        return DDSEncoder.rgba8888(face)
    }

    private static func fnv1a(_ text: String) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }
}
