// How the effect models reach the renderer: posed copies, plain placements, and the
// particle systems their meshes carry.

import Foundation
import OpenSkyAudio
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyShaderTypes
import OpenSkyWorldInterface
import simd

/// The drawing part of `EffectsCoordinator`. It holds the mesh library and the particle
/// state, not the coordinator.
final class EffectModelDrawing {
    let meshes: MeshLibrary?
    /// Poses effect models that run their own animation graph.
    weak var posing: (any EffectModelPosing)?
    private(set) var failedModels: Set<String> = []
    /// The particle systems of each live effect, by instance id.
    private var particles: [Int: EffectParticles] = [:]
    private var drewModels = false

    init(meshes: MeshLibrary?) {
        self.meshes = meshes
    }

    /// Hands the renderer this frame's models: the effects' own, posed where a graph runs
    /// them, then `models.extra`, the debris and hazard models other runtimes own.
    func draw(
        _ models: (effects: [VisualEffectModel], extra: [VisualEffectModel]),
        seconds: Float, renderer: Renderer
    ) throws {
        let posed = posing?.pose(models.effects, deltaTime: seconds) ?? [:]
        let all = models.effects + models.extra
        try syncParticles(all, posed: posed, renderer: renderer)
        let meshParticles = particles.keys.sorted()
            .flatMap { particles[$0]?.playbacks ?? [] }
            .flatMap { $0.meshPlacements() }
        guard !all.isEmpty || drewModels else { return }
        let placements = models.effects.compactMap { model -> RenderPlacement? in
            if let id = model.instanceID, let copy = posed[id] {
                return RenderPlacement(
                    model: copy.model, transform: model.transform,
                    castsShadows: false, layer: .particles
                )
            }
            return placement(model)
        } + models.extra.compactMap(placement) + meshParticles
        try renderer.setEffectPlacements(
            placements, animations: posed.keys.sorted().compactMap { posed[$0]?.animation }
        )
        drewModels = !all.isEmpty
    }

    private func placement(_ model: VisualEffectModel) -> RenderPlacement? {
        guard let meshes, !failedModels.contains(model.path) else { return nil }
        do {
            return try RenderPlacement(
                model: meshes.model(path: model.path),
                transform: model.transform,
                castsShadows: false,
                layer: .particles
            )
        } catch {
            failedModels.insert(model.path)
            return nil
        }
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
            if var existing = particles[id] {
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
        changed = changed || particles.keys.contains { id in
            live[id] == nil && particles[id]?.playbacks.isEmpty == false
        }
        particles = live
        if changed {
            try renderer
                .setEffectParticles(live.keys.sorted().flatMap { live[$0]?.playbacks ?? [] })
        }
    }
}
