// What an impact leaves behind: its IPCT model at the contact point and its decal
// on the struck surface. Footsteps, melee hits, and projectile hits come here
// after their sound. See docs/rendering/decals.md.

import Foundation
import OpenSkyAudio
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyRendering
import OpenSkyShaderTypes
import simd

/// Where an impact's decal goes.
nonisolated public enum ImpactSurface: Equatable, Sendable {
    /// A surface with a known normal, such as a wall an arrow struck.
    case surface(normal: SIMD3<Float>)
    /// An actor's body. OpenSky has no skin decals, so the mark goes on the
    /// ground under the actor.
    case actor(ReferenceKey)
    /// The ground under a foot.
    case ground
}

/// The particle systems one live effect owns, and where they were placed.
struct EffectParticles {
    let playbacks: [ParticlePlayback]
    var origin: SIMD3<Float>
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
        if decals.place(look, at: decalPosition(position, on: surface), normal: normal) != nil {
            decalsChanged = true
        }
    }

    /// The last impact at the player's feet, on the ground. False before the first one.
    @discardableResult
    public func repeatLastImpact() -> Bool {
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

    public func clearDecals() {
        decals.removeAll()
        decalsChanged = true
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

    /// Starts the particle systems of new effects, moves those of moving ones, and
    /// drops those of effects that ended.
    func syncParticles(_ models: [VisualEffectModel], renderer: Renderer) {
        guard let meshes else { return }
        var live: [Int: EffectParticles] = [:]
        var changed = false
        for model in models {
            guard let id = model.instanceID else { continue }
            let origin = SIMD3(
                model.transform.columns.3.x,
                model.transform.columns.3.y,
                model.transform.columns.3.z
            )
            if var existing = effectParticles[id] {
                let delta = origin - existing.origin
                if simd_length_squared(delta) > 0 {
                    existing.playbacks.forEach { $0.translate(by: delta) }
                    existing.origin = origin
                }
                live[id] = existing
                continue
            }
            let playbacks = (try? meshes.particlePlaybacks(
                path: model.path, placementTransform: model.transform, formID: UInt32(id)
            )) ?? []
            live[id] = EffectParticles(playbacks: playbacks, origin: origin)
            changed = changed || !playbacks.isEmpty
        }
        changed = changed || effectParticles.keys.contains { id in
            live[id] == nil && effectParticles[id]?.playbacks.isEmpty == false
        }
        effectParticles = live
        if changed {
            renderer.setEffectParticles(live.keys.sorted().flatMap { live[$0]?.playbacks ?? [] })
        }
    }

    /// Hands the renderer the decals, one batch per texture, after a change.
    func syncDecals(renderer: Renderer) throws {
        guard decalsChanged, let meshes else { return }
        decalsChanged = false
        var order: [String] = []
        var byTexture: [String: [DecalInstance]] = [:]
        for decal in decals.decals {
            if byTexture[decal.look.texture] == nil {
                order.append(decal.look.texture)
            }
            byTexture[decal.look.texture, default: []].append(DecalInstance(
                center: SIMD4(decal.center, 1),
                axisU: SIMD4(decal.axisU, 0),
                axisV: SIMD4(decal.axisV, 0),
                color: SIMD4(decal.look.color, 1),
                uvRect: decal.uvRect
            ))
        }
        try renderer.setDecals(order.map { key in
            DecalBatch(
                texture: meshes.textures.texture(key: key, usage: .color),
                instances: byTexture[key] ?? []
            )
        })
    }
}
