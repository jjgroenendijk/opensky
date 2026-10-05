// App side of visual and audio effects: hands the load-order effect records
// to the image-space resolve, the explosion runtime, and the effects
// coordinator; routes spell hits; and steps debris and effects each frame.
// The rules live in the coordinators (docs/rendering/visual-effects.md).

import Foundation
import OpenSkyCombat
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyPhysics
import OpenSkyRendering
import OpenSkyWorld
import OpenSkyWorldState
import simd

final class EffectsWorldAdapter {
    /// A long frame steps as this, as for hazards.
    static let longestStep: Float = 0.25
    /// Base plugin of the streamed cells and the item and sound indexes.
    static let basePlugin = "Skyrim.esm"

    unowned let game: GameViewController
    private(set) var cameraPosition: SIMD3<Float>?
    /// Actors whose race abilities were looked at, so each is resolved once.
    private var raceChecked: Set<ReferenceKey> = []
    private var spawnedHazards: UInt64 = 0
    private var lastFrame: Date?

    init(game: GameViewController) {
        self.game = game
    }

    var effects: EffectsCoordinator {
        game.effects
    }

    var explosions: ExplosionRuntime {
        game.combat.explosions
    }

    func wireEffects(provider: any WorldDataProviding, streamer: CellStreamer, renderer: Renderer) {
        guard let records = (provider as? EffectDataProviding)?.effectRecords else { return }
        renderer.session.imageSpaceLinks = ImageSpaceLinks(
            records: records, weatherPlugin: Self.basePlugin
        )
        effects.wire(records: records, meshes: Self.meshes(provider: provider, renderer: renderer))
        effects.world = self
        explosions.records = records
        explosions.itemPlugin = Self.basePlugin
        explosions.world = self
        game.magic.onSpellHit = { [weak self, weak renderer] event in
            guard let self, let renderer else { return }
            effects.handleSpellHit(event, imageSpace: &renderer.imageSpace)
        }
        renderer.onFrame.add { [weak self, weak renderer, weak streamer] position in
            guard let self, let renderer else { return }
            cameraPosition = position
            tick(renderer: renderer, streamer: streamer)
        }
    }

    /// A main-thread library of its own: the cell build queue owns the other one.
    private static func meshes(
        provider: any WorldDataProviding,
        renderer: Renderer
    ) -> MeshLibrary? {
        guard
            let fileSystem = (provider as? ScriptDataProviding)?.scriptFileSystem,
            let textures = try? TextureLibrary(fileSystem: fileSystem, device: renderer.device)
        else { return nil }
        return MeshLibrary(fileSystem: fileSystem, device: renderer.device, textures: textures)
    }

    /// Steps by wall-clock time, and not at all while a menu pauses the world. The
    /// interior's image space and the effect draw lists update every frame.
    private func tick(renderer: Renderer, streamer: CellStreamer?, now: Date = Date()) {
        renderer.session.imageSpaceLinks?.interior = streamer?.interiorScene.map {
            InteriorImageSpace(imageSpace: $0.imageSpace, plugin: Self.basePlugin)
        }
        let paused = renderer.worldSimPaused
        let elapsed = lastFrame.map { Float(now.timeIntervalSince($0)) } ?? 0
        let seconds = paused ? 0 : min(elapsed, Self.longestStep)
        lastFrame = paused ? nil : now
        attachRaceEffects()
        explosions.advance(seconds)
        do {
            try effects.step(seconds, extraModels: extraModels(), renderer: renderer)
        } catch {
            GameViewController.logger.error(
                "[ERROR] effect draw lists: \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// Debris pieces and the models of spawned hazards, drawn beside the effects.
    private func extraModels() -> [VisualEffectModel] {
        let debris = explosions.debris.map {
            VisualEffectModel(path: $0.path, transform: $0.transform)
        }
        let hazards = game.hazards.runtime.active.values
            .filter { $0.source == .spawned }
            .sorted { $0.id < $1.id }
            .compactMap { hazard -> VisualEffectModel? in
                guard let path = game.hazardWorld.store?.modelPath(for: hazard.spec.hazard) else {
                    return nil
                }
                var transform = matrix_identity_float4x4
                transform.columns.3 = SIMD4(hazard.position, 1)
                return VisualEffectModel(path: path, transform: transform)
            }
        return debris + hazards
    }

    /// Lasting race-ability looks for actors that arrived, and their removal for
    /// actors that left.
    private func attachRaceEffects() {
        let resident = game.streamer?.residentActorEntries() ?? []
        let keys = Set(resident.map(\.key))
        for gone in raceChecked.subtracting(keys) {
            effects.detachAll(from: gone)
        }
        raceChecked.formIntersection(keys)
        for entry in resident where !raceChecked.contains(entry.key) {
            guard let base = entry.placedActor?.base else { continue }
            raceChecked.insert(entry.key)
            effects.attachLasting(
                game.magic.raceEffectLinks(base: base, actor: entry.key),
                to: entry.key
            )
        }
    }

    /// A generated key no world-state spawn uses: the top bit marks effect spawns.
    func nextHazardKey() -> ReferenceKey {
        spawnedHazards += 1
        return .generated(0x8000_0000_0000_0000 | spawnedHazards)
    }
}

extension EffectsWorldAdapter: ExplosionWorld {
    func explosionTargets() -> [MeleeTarget] {
        game.hazardWorld.hazardCandidates()
    }

    func explosionViewer() -> SIMD3<Float>? {
        cameraPosition
    }

    func applyExplosionDamage(_ amount: Float, to target: ReferenceKey) -> Bool {
        game.combat.applyHealthDamage(amount, to: target, attacker: nil)
    }

    /// The sound index is built from the base plugin, so only its sounds play.
    func playExplosionSound(_ sound: ReferenceKey, at position: SIMD3<Float>) {
        guard
            case let .plugin(name, objectID) = sound,
            name == Self.basePlugin.lowercased() else { return }
        game.audio.soundDirector?.forcePlaySound(formID: FormID(objectID), position: position)
    }

    func startExplosionImageSpace(_ modifier: ReferenceKey, strength: Float) {
        guard let renderer = game.renderer else { return }
        effects.startModifier(modifier, strength: strength, on: &renderer.imageSpace)
    }

    func placeExplosionHazard(_ hazard: ReferenceKey, at position: SIMD3<Float>) -> Bool {
        guard let spec = game.hazardWorld.store?.spec(for: hazard) else { return false }
        game.hazards.spawn(HazardPlacement(id: nextHazardKey(), spec: spec, position: position))
        return true
    }

    func showExplosionModel(_ path: String, at position: SIMD3<Float>) {
        effects.showModel(path, at: position, cause: .explosion)
    }
}

extension EffectsWorldAdapter: EffectsWorld {
    /// An actor's feet turned to its facing; the player's turn with the camera.
    func effectTransform(of actor: ReferenceKey) -> float4x4? {
        if actor == .player {
            guard let renderer = game.renderer else { return nil }
            let look = renderer.camera.target - renderer.camera.eye
            return Self.transform(
                feet: renderer.locomotion.status.feetPosition,
                yaw: atan2(look.y, look.x)
            )
        }
        guard let observed = game.actorWorld.combatActors().first(where: { $0.key == actor }) else {
            return nil
        }
        return Self.transform(feet: observed.feet, yaw: observed.facing)
    }

    func membraneTarget(of actor: ReferenceKey) -> MembraneTarget? {
        switch actor {
        case .player: .player
        case let .plugin(_, objectID): .actor(objectID)
        default: nil
        }
    }

    func detonateEffectExplosion(_ explosion: ReferenceKey, at position: SIMD3<Float>) {
        guard let spec = explosions.spec(for: explosion) else { return }
        explosions.detonate(spec, at: position, cause: .spell)
    }

    private static func transform(feet: SIMD3<Float>, yaw: Float) -> float4x4 {
        var matrix = float4x4(simd_quatf(angle: yaw, axis: SIMD3(0, 0, 1)))
        matrix.columns.3 = SIMD4(feet, 1)
        return matrix
    }
}

extension EffectsWorldAdapter: ExplosionControlWorld {
    /// How far in front of the camera a panel detonation lands, in world units.
    static let viewDistance: Float = 300

    var effectsViewPoint: SIMD3<Float>? {
        guard let camera = game.renderer?.camera else { return nil }
        let look = camera.target - camera.eye
        guard simd_length(look) > 0 else { return nil }
        return camera.eye + simd_normalize(look) * Self.viewDistance
    }

    var hazardNames: [String] {
        game.hazardWorld.store?.hazards.records.compactMap(\.record.editorID).sorted() ?? []
    }

    func spawnHazard(named name: String, at position: SIMD3<Float>) -> Bool {
        guard let resolved = game.hazardWorld.store?.hazards.record(editorID: name)
        else { return false }
        return placeExplosionHazard(ReferenceKey(resolved: resolved.id), at: position)
    }

    var hazardRows: [TrapHazardRow] {
        game.hazards.hazardRows
    }
}
