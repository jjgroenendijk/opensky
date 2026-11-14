// Picks the resident level of every streamed texture from the camera distance of the
// surfaces that use it, then fits the budget. Runs a few times per second, not every
// frame. See docs/rendering/texture-streaming.md.

import Metal
import OpenSkyFormatsCore
import OpenSkyRenderCore
import OpenSkyRenderResources
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
        // map must not lower it under the grass at the player's feet.
        let grass = Set(scene.grass.flatMap { group in
            group.material.streamedMaps(uvPerUnit: 0).map { ObjectIdentifier($0.texture) }
        })
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
        if textureStreaming.enabled {
            drainNearlyEmptyHeap()
        }
    }

    /// Moves the tiles out of a nearly empty heap, so the heap can be freed. Each texture
    /// with tiles there drops the levels that use them. The next update reads those levels
    /// again, and their new tiles come from fuller heaps.
    private func drainNearlyEmptyHeap() {
        guard let heap = textureStreaming.pool.heapToDrain() else { return }
        for entry in textureStreaming.entries.values
            where entry.texture != nil && entry.unmapAfterFrame == nil
        {
            var coarsest = -1
            for (level, tiles) in entry.tiles where level < entry.layout.floorLevel {
                guard level > coarsest else { continue }
                for tile in tiles where tile.heap == heap {
                    coarsest = level
                    break
                }
            }
            if coarsest >= 0 {
                lower(entry, to: coarsest + 1)
            }
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

    /// The use of each texture the scene draws that needs the most texels per pixel. Every
    /// map of a material is measured at the same surface as its diffuse.
    func nearestUses() -> [ObjectIdentifier: TextureUse] {
        let camera = frameInput.view.position
        var nearest: [ObjectIdentifier: TextureUse] = [:]
        func note(_ texture: any MTLTexture, bounds: ModelBounds, uvPerUnit: Float) {
            let use = TextureUse(bounds: bounds, camera: camera, uvPerUnit: uvPerUnit)
            let key = ObjectIdentifier(texture)
            if use.isFiner(than: nearest[key]) {
                nearest[key] = use
            }
        }
        func note(_ material: RenderMaterial, bounds: ModelBounds, uvPerUnit: Float) {
            material.forEachStreamedMap(uvPerUnit: uvPerUnit) { texture, perUnit in
                note(texture, bounds: bounds, uvPerUnit: perUnit)
            }
        }
        for list in [frameDrawGroups.opaque, frameDrawGroups.alphaTested] {
            for index in list.indices {
                // Every map of the material scales its density with the instance, but a
                // landscape noise map, whose density is fixed. So the finest instance and
                // the nearest one are the only two that can need the most of any map.
                let pair = finestUses(of: list[index], camera: camera)
                guard let finest = pair.finest, let nearest = pair.nearest else { continue }
                note(list[index].material, bounds: finest.bounds, uvPerUnit: finest.uvPerUnit)
                note(list[index].material, bounds: nearest.bounds, uvPerUnit: nearest.uvPerUnit)
            }
        }
        for item in scene.terrain {
            guard let bounds = item.bounds else { continue }
            let normals = [item.normals.base] + item.normals.layers
            for texture in [item.material.diffuse] + item.layerTextures + normals {
                note(texture, bounds: bounds, uvPerUnit: 1 / Self.terrainRepeatUnits)
            }
        }
        // The arms ride the eye and carry no bounds, so they count as at the camera.
        let atEye = ModelBounds(min: camera, max: camera)
        for group in firstPersonArmGroups {
            let uvScale = max(group.material.uvScale.x, group.material.uvScale.y)
            note(group.material, bounds: atEye, uvPerUnit: group.mesh.uvPerUnit * uvScale)
        }
        return nearest
    }
}

extension Renderer {
    /// One instance's surface: its bounds where it draws and its UV density.
    struct InstanceSurface {
        let bounds: ModelBounds
        let uvPerUnit: Float
    }

    /// The group's instance with the most texels per pixel, and its nearest instance,
    /// each the first of its kind in the group's order.
    func finestUses(
        of group: DrawGroup, camera: SIMD3<Float>
    ) -> (finest: InstanceSurface?, nearest: InstanceSurface?) {
        let uvScale = max(group.material.uvScale.x, group.material.uvScale.y)
        var finest: (use: TextureUse, surface: InstanceSurface)?
        var nearest: (use: TextureUse, surface: InstanceSurface)?
        // A rider or a walker is far from its baked bounds; measure where it draws.
        for placed in group.instances {
            let instance = drawn(placed)
            guard let bounds = instance.bounds else { continue }
            let axis = instance.modelMatrix.columns.0
            let scale = max(simd_length(SIMD3(axis.x, axis.y, axis.z)), 0.01)
            let surface = InstanceSurface(
                bounds: bounds, uvPerUnit: group.mesh.uvPerUnit * uvScale / scale
            )
            let use = TextureUse(bounds: bounds, camera: camera, uvPerUnit: surface.uvPerUnit)
            if use.isFiner(than: finest?.use) {
                finest = (use, surface)
            }
            let near = TextureUse(bounds: bounds, camera: camera, uvPerUnit: 1)
            if near.isFiner(than: nearest?.use) {
                nearest = (near, surface)
            }
        }
        return (finest?.surface, nearest?.surface)
    }

    /// The arm groups drawn this frame, which are not in `frameDrawGroups`.
    var firstPersonArmGroups: [DrawGroup] {
        guard areFirstPersonArmsVisible, let rig = frameInput.rigs.arms else { return [] }
        return rig.render.opaque + rig.render.alphaTested
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
