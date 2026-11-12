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
        if impactModelsEnabled, let path = impact.modelPath {
            let anchor: EffectAnchor = impact.facesSurface
                ? .surface(position, normal: normal) : .point(position)
            visualEffects.attach(
                VisualEffectSpec(name: path, artModel: path, membrane: nil),
                to: anchor,
                cause: .impact,
                duration: Self.instantArtDuration
            )
        }
        guard let look = decal?.look else { return }
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

    /// Hands the renderer the decals, one batch per texture, after a change.
    /// Skin decals move with their actors, so a frame with any rebuilds the batches.
    func syncDecals(renderer: Renderer) throws {
        let onActors = skinDecals.worldDecals { [world] key in world?.skinDecalFrames(of: key) }
        guard decalsChanged || !onActors.isEmpty, let meshes else { return }
        decalsChanged = !onActors.isEmpty
        let placed = decals.decals.map { ($0, false) } + onActors.map { ($0, true) }
        try renderer.setDecals(EffectDecalBatches.batches(placed, textures: meshes.textures))
    }
}

nonisolated extension Impact {
    /// Nil when the impact shows no model.
    var modelPath: String? {
        model.map(\.path).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Orientation 0 turns the model to the surface; the others follow the
    /// projectile, which a contact point does not carry, so they stand upright.
    var facesSurface: Bool {
        effect?.orientation == 0
    }
}

nonisolated extension ImpactDecal {
    /// Nil without a texture or a positive size.
    var look: DecalLook? {
        NIFShaderTextureSet.vfsKey(for: diffusePath).flatMap {
            DecalLook(texture: $0, decal: decal)
        }
    }
}
