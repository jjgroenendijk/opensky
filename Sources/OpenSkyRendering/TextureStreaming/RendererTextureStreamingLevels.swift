// Picks the resident level of every streamed texture from the camera distance of the
// surfaces that use it, then fits the budget. Runs a few times per second, not every
// frame. See docs/rendering/texture-streaming.md.

import Metal
import OpenSkyFormatsCore
import simd

extension Renderer {
    /// Frames between two level updates.
    static let textureStreamingInterval = 8
    /// A landscape texture repeats every two terrain quads (docs/engine/terrain.md).
    static let terrainRepeatUnits: Float = 256

    func updateStreamedLevels() {
        let entries = Array(textureStreaming.entries.values)
        guard !entries.isEmpty else { return }
        let nearest = textureStreaming.enabled ? nearestUses() : [:]
        let inScene = Set(sceneAllocations.map(ObjectIdentifier.init))
        // Grass has no per-instance measure, so a static far away that shares its
        // texture must not lower it under the grass at the player's feet.
        let grass = Set(scene.grass.map { ObjectIdentifier($0.material.diffuse) })
        var demands: [TextureDemand] = []
        for entry in entries {
            guard let texture = entry.texture else {
                demands.append(TextureDemand(
                    layout: entry.layout, wantedLevel: entry.layout.floorLevel,
                    distance: .greatestFiniteMagnitude
                ))
                continue
            }
            let key = ObjectIdentifier(texture)
            let use = grass.contains(key) ? nil : nearest[key]
            demands.append(demand(for: entry, use: use, inScene: inScene.contains(key)))
        }
        let budgetTiles = textureStreaming.budgetBytes / textureStreaming.pool.tileBytes
        let levels = textureStreaming.enabled
            ? TextureStreamingPolicy.fit(demands, budgetTiles: budgetTiles)
            : demands.map { _ in 0 }
        let overBudget = textureStreaming.pool.usedTiles > budgetTiles
        for (entry, level) in zip(entries, levels) {
            apply(level, to: entry, overBudget: overBudget)
        }
    }

    private func demand(
        for entry: StreamedTextureEntry, use: TextureUse?, inScene: Bool
    ) -> TextureDemand {
        guard let use else {
            // A scene texture the rule does not measure, such as grass, stays whole. One
            // outside the scene lists, such as the player's body, keeps its level.
            let level = inScene ? 0 : min(entry.residentLevel, entry.layout.floorLevel)
            return TextureDemand(layout: entry.layout, wantedLevel: level, distance: 0)
        }
        let level = TextureStreamingPolicy.neededLevel(
            textureSize: max(entry.layout.width, entry.layout.height),
            uvPerUnit: use.uvPerUnit, distance: use.distance, view: streamingView
        )
        return TextureDemand(layout: entry.layout, wantedLevel: level, distance: use.distance)
    }

    private func apply(_ level: Int, to entry: StreamedTextureEntry, overBudget: Bool) {
        if level < entry.residentLevel {
            guard
                entry.requestedLevel == nil, entry.unmapAfterFrame == nil,
                let texture = entry.texture, let reader = textureStreaming.reader
            else { return }
            entry.requestedLevel = level
            reader.requestTextureLevels(
                TextureLevelRequest(texture: texture, source: entry.source, firstLevel: level),
                mailbox: textureStreaming.mailbox
            )
        } else if level > entry.residentLevel + 1 || (overBudget && level > entry.residentLevel) {
            // One level of slack, so a texture near the line does not flip each update.
            lower(entry, to: overBudget ? level : level - 1)
        }
    }

    private var streamingView: TextureStreamingView {
        TextureStreamingView(
            viewHeight: textureStreaming.viewHeight,
            tanHalfFOV: tan(FirstPersonCamera.defaultFOVYRadians / 2)
        )
    }

    /// The use of each texture the scene draws that needs the most texels per pixel.
    private func nearestUses() -> [ObjectIdentifier: TextureUse] {
        let camera = freeFlyCamera.position
        var nearest: [ObjectIdentifier: TextureUse] = [:]
        func note(_ texture: MTLTexture, bounds: ModelBounds, uvPerUnit: Float) {
            let use = TextureUse(bounds: bounds, camera: camera, uvPerUnit: uvPerUnit)
            let key = ObjectIdentifier(texture)
            if use.isFiner(than: nearest[key]) {
                nearest[key] = use
            }
        }
        for group in [frameDrawGroups.opaque, frameDrawGroups.alphaTested].joined() {
            let uvScale = max(group.material.uvScale.x, group.material.uvScale.y)
            for instance in group.instances {
                guard let bounds = instance.bounds else { continue }
                let axis = instance.modelMatrix.columns.0
                let scale = max(simd_length(SIMD3(axis.x, axis.y, axis.z)), 0.01)
                note(
                    group.material.diffuse, bounds: bounds,
                    uvPerUnit: group.mesh.uvPerUnit * uvScale / scale
                )
            }
        }
        for item in scene.terrain {
            guard let bounds = item.bounds else { continue }
            for texture in [item.material.diffuse] + item.layerTextures {
                note(texture, bounds: bounds, uvPerUnit: 1 / Self.terrainRepeatUnits)
            }
        }
        return nearest
    }
}

/// The surface that needs the most of one texture: its distance and UV density.
struct TextureUse {
    let distance: Float
    let uvPerUnit: Float

    init(bounds: ModelBounds, camera: SIMD3<Float>, uvPerUnit: Float) {
        distance = simd_distance(camera, simd_clamp(camera, bounds.min, bounds.max))
        self.uvPerUnit = uvPerUnit
    }

    /// Texels per pixel grow with this, so the larger value needs the finer level.
    var texelsPerPixelScale: Float {
        uvPerUnit / max(distance, 1)
    }

    func isFiner(than other: TextureUse?) -> Bool {
        guard let other else { return true }
        return texelsPerPixelScale > other.texelsPerPixelScale
    }
}
