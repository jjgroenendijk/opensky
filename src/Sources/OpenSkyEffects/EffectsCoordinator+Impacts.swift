// What an impact leaves behind: its IPCT model at the contact point and its decal
// on the struck surface. Footsteps, melee hits, and projectile hits come here
// after their sound. See docs/rendering/decals.md.

import Foundation
public import OpenSkyAudio
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyShaderTypes
public import OpenSkyWorldInterface
public import simd

/// The particle systems one live effect owns, and where they were placed.
struct EffectParticles {
    let playbacks: [ParticlePlayback]
    var placement: float4x4
}

extension EffectsCoordinator {
    /// Shows `impact`'s model at `position`, and places `decal` on `surface`.
    public func showImpact(
        _ impact: Impact,
        decal: ImpactDecal?,
        at position: SIMD3<Float>,
        on surface: ImpactSurface
    ) {
        impactCount += 1
        lastImpact = (impact, decal)
        let normal = surfaceNormal(surface)
        if impactModelsEnabled, let path = impact.model?.path, !path.isEmpty {
            // Orientation 0 turns the model to the surface; the others follow the
            // projectile, which a contact point does not carry, so they stand upright.
            let anchor: EffectAnchor = impact.effect?.orientation == 0
                ? .surface(position, normal: normal) : .point(position)
            visualEffects.attach(
                VisualEffectSpec(name: path, artModel: path, membrane: nil),
                to: anchor,
                cause: .impact,
                duration: Self.instantArtDuration
            )
        }
        guard
            let decal,
            let key = NIFShaderTextureSet.vfsKey(for: decal.diffusePath),
            let look = DecalLook(texture: key, decal: decal.decal)
        else { return }
        if
            case let .actor(key) = surface, skinDecals.decals.enabled,
            let frame = world?.effectTransform(of: key)
        {
            skinDecals.place(
                look, on: key, at: position, ownerTransform: frame,
                bones: world?.effectBones(of: key) ?? [:]
            )
            return
        }
        if decals.place(look, at: decalPosition(position, on: surface), normal: normal) != nil {
            decalsChanged = true
        }
    }

    /// The last impact at the player's feet, on the ground. False before the first one.
    @discardableResult
    func repeatLastImpact() -> Bool {
        guard let last = lastImpact, let feet = world?.effectTransform(of: .player)?.columns.3
        else { return false }
        showImpact(last.impact, decal: last.decal, at: SIMD3(feet.x, feet.y, feet.z), on: .ground)
        return true
    }

    public var decalsEnabled: Bool {
        get { decals.enabled }
        set {
            decals.enabled = newValue
            if !newValue {
                clearDecals()
            }
        }
    }

    public var decalLimit: Int {
        get { decals.limit }
        set {
            decals.limit = max(newValue, 0)
            decalsChanged = true
        }
    }

    func clearDecals() {
        decals.removeAll()
        skinDecals.removeAll()
        decalsChanged = true
    }

    /// The game's `bSkinnedDecals`; off clears the marks on actors.
    public var skinDecalsEnabled: Bool {
        get { skinDecals.decals.enabled }
        set {
            skinDecals.decals.enabled = newValue
            if !newValue {
                skinDecals.removeAll()
                decalsChanged = true
            }
        }
    }

    private func surfaceNormal(_ surface: ImpactSurface) -> SIMD3<Float> {
        guard case let .surface(normal) = surface, simd_length_squared(normal) > 1e-8 else {
            return SIMD3(0, 0, 1)
        }
        return simd_normalize(normal)
    }

    private func decalPosition(
        _ position: SIMD3<Float>,
        on surface: ImpactSurface
    ) -> SIMD3<Float> {
        guard
            case let .actor(key) = surface,
            let feet = world?.effectTransform(of: key)?.columns.3
        else { return position }
        return SIMD3(position.x, position.y, feet.z)
    }

    /// A model's up turned to `normal`, at `position`.
    static func surfaceTransform(_ position: SIMD3<Float>, normal: SIMD3<Float>) -> float4x4 {
        let up = simd_length_squared(normal) > 1e-8 ? simd_normalize(normal) : SIMD3(0, 0, 1)
        let (tangent, bitangent) = DecalRuntime.basis(around: up, angle: 0)
        return float4x4(columns: (
            SIMD4(tangent, 0), SIMD4(bitangent, 0), SIMD4(up, 0), SIMD4(position, 1)
        ))
    }

    /// Starts the particle systems of new effects, moves the emitters of moving ones, and
    /// drops those of effects that ended.
    func syncParticles(
        _ models: [VisualEffectModel], posed: [Int: PosedEffectModel] = [:], renderer: Renderer
    ) throws {
        guard let meshes else { return }
        var live: [Int: EffectParticles] = [:]
        var changed = false
        for model in models {
            guard let id = model.instanceID else { continue }
            defer {
                if let sequence = posing?.playedSequence(ofEffect: id) {
                    live[id]?.playbacks.forEach { $0.play(sequence: sequence) }
                }
            }
            if var existing = effectParticles[id] {
                if let nodes = posed[id]?.nodeDeltas {
                    // A posed model's nodes move each frame, so its emitters follow them.
                    for playback in existing.playbacks {
                        playback.move(to: model.transform, nodeDeltas: nodes)
                    }
                    existing.placement = model.transform
                } else if existing.placement != model.transform {
                    existing.playbacks.forEach { $0.move(to: model.transform) }
                    existing.placement = model.transform
                }
                live[id] = existing
                continue
            }
            let playbacks = attempt {
                try meshes.particlePlaybacks(
                    path: model.path, placementTransform: model.transform, formID: UInt32(id)
                )
            } ?? []
            live[id] = EffectParticles(playbacks: playbacks, placement: model.transform)
            changed = changed || !playbacks.isEmpty
        }
        changed = changed || effectParticles.keys.contains { id in
            live[id] == nil && effectParticles[id]?.playbacks.isEmpty == false
        }
        effectParticles = live
        if changed {
            try renderer
                .setEffectParticles(live.keys.sorted().flatMap { live[$0]?.playbacks ?? [] })
        }
    }

    /// Hands the renderer the decals, one batch per texture, after a change.
    /// Skin decals move with their actors, so a frame with any rebuilds the batches.
    func syncDecals(renderer: Renderer) throws {
        let onActors = skinDecals.worldDecals { [world] key in
            world.map { world in
                SkinDecalFrames(
                    feet: world.effectTransform(of: key),
                    bones: world.effectBones(of: key)
                )
            }
        }
        guard decalsChanged || !onActors.isEmpty, let meshes else { return }
        decalsChanged = !onActors.isEmpty
        var order: [DecalBatchKey] = []
        var byKey: [DecalBatchKey: [DecalInstance]] = [:]
        let placed = decals.decals.map { ($0, false) } + onActors.map { ($0, true) }
        for (decal, projected) in placed {
            let key = DecalBatchKey(texture: decal.look.texture, projected: projected)
            if byKey[key] == nil {
                order.append(key)
            }
            // A skin decal's box reaches as deep as its widest side, to wrap a limb.
            let depth = projected ? max(simd_length(decal.axisU), simd_length(decal.axisV)) : 0
            byKey[key, default: []].append(DecalInstance(
                center: SIMD4(decal.center, depth),
                axisU: SIMD4(decal.axisU, 0),
                axisV: SIMD4(decal.axisV, 0),
                color: SIMD4(decal.look.color, 1),
                uvRect: decal.uvRect
            ))
        }
        try renderer.setDecals(order.map { key in
            DecalBatch(
                texture: meshes.textures.texture(key: key.texture, usage: .color),
                instances: byKey[key] ?? [],
                projected: key.projected
            )
        })
    }
}

private struct DecalBatchKey: Hashable {
    let texture: String
    let projected: Bool
}
