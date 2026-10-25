// App side of visual and audio effects: hands the load-order effect records
// to the image-space resolve, the explosion runtime, and the effects
// coordinator; routes spell hits; and steps debris and effects each frame.
// The rules live in the coordinators (docs/rendering/visual-effects.md).

import Foundation
import OpenSkyCells
import OpenSkyCombat
import OpenSkyEffects
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyMenus
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldState
import simd

/// What `EffectsWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
protocol EffectsWorldHost: AnyObject {
    var actorWorld: ActorWorldAdapter { get }
    var audio: AudioCoordinator { get }
    var combat: CombatCoordinator { get }
    var effects: EffectsCoordinator { get set }
    var playerSettings: PlayerSettingsCoordinator { get }
    var worldData: WorldDataStores? { get }
    var hazardWorld: HazardWorldAdapter { get }
    var hazards: HazardCoordinator { get }
    var magic: MagicCoordinator { get }
    var magicWorld: MagicWorldAdapter { get }
    var ragdoll: RagdollCoordinator { get }
    var renderer: Renderer? { get }
    var gameSession: GameSession? { get }
    var scripts: ScriptCoordinator { get }
    var streamer: CellStreamer? { get }
    var worldState: WorldStateStore { get }
}

final class EffectsWorldAdapter {
    /// A long frame steps as this, as for hazards.
    static let longestStep: Float = 0.25
    /// Base plugin of the streamed cells and the item and sound indexes.
    static let basePlugin = "Skyrim.esm"

    unowned let game: any EffectsWorldHost
    private(set) var cameraPosition: SIMD3<Float>?
    /// Actors whose race abilities were looked at, so each is resolved once.
    private var raceChecked: Set<ReferenceKey> = []
    private var spawnedHazards: UInt64 = 0
    private var lastFrame: Date?

    init(game: any EffectsWorldHost) {
        self.game = game
    }

    var effects: EffectsCoordinator {
        game.effects
    }

    var explosions: ExplosionRuntime {
        game.combat.explosions
    }

    func wireEffects(provider: WorldDataStores, streamer: CellStreamer, gameSession: GameSession) {
        guard let records = provider.effectRecords else { return }
        gameSession.imageSpaceLinks = ImageSpaceLinks(
            records: records, weatherPlugin: Self.basePlugin
        )
        game.effects.applyGraphicsSettings(game.playerSettings.store)
        let frameSteps = gameSession.frameSteps
        frameSteps.register(.effects) { [weak self, weak gameSession, weak streamer] position in
            guard let self, let gameSession else { return }
            cameraPosition = position
            tick(gameSession: gameSession, streamer: streamer)
        }
    }

    /// The visual, image-space, and sound side of one landed spell.
    func handleSpellHit(_ event: SpellHitEvent) {
        guard let gameSession = game.gameSession else { return }
        effects.handleSpellHit(event, imageSpace: &gameSession.imageSpace)
        noteSpellHit(event.hit)
        playHitSounds(of: event, director: gameSession.soundDirector)
    }

    /// The explosion runtime the combat coordinator owns. Without effect records it
    /// has no world, and nothing detonates.
    func makeExplosions() -> ExplosionRuntime {
        guard let records = game.worldData?.effectRecords else { return ExplosionRuntime() }
        return ExplosionRuntime(records: records, itemPlugin: Self.basePlugin, world: self)
    }

    /// A hostile spell's push on a body it kills: the sum of its magnitudes as the
    /// damage, from where it landed. OpenSky's reading (docs/engine/ragdoll.md).
    private func noteSpellHit(_ hit: SpellHit) {
        guard hit.payload.isHostile else { return }
        let damage = hit.payload.entries.reduce(0) { $0 + max($1.magnitude, 0) }
        for target in hit.targets {
            game.ragdoll.noteHit(
                CombatHitRecord(
                    damage: damage, kind: .spell, attacker: hit.payload.caster, origin: hit.impact
                ),
                on: target.key
            )
        }
    }

    /// Each effect's On Hit sound, at each struck actor.
    private func playHitSounds(of event: SpellHitEvent, director: WorldAudioSoundDirector?) {
        guard let director else { return }
        for sound in event.links.compactMap(\.hitSound) {
            for target in event.hit.targets {
                guard let transform = effectTransform(of: target.key) else { continue }
                let origin = transform.columns.3
                director.forcePlaySound(
                    formID: sound,
                    position: SIMD3(origin.x, origin.y, origin.z)
                )
            }
        }
    }

    /// A main-thread library of its own: the cell build queue owns the other one.
    static func meshes(
        provider: WorldDataStores,
        renderer: Renderer
    ) -> MeshLibrary? {
        guard
            let fileSystem = provider.scriptFileSystem,
            let textures = try? TextureLibrary(fileSystem: fileSystem, device: renderer.device)
        else { return nil }
        return MeshLibrary(fileSystem: fileSystem, device: renderer.device, textures: textures)
    }

    /// Steps by wall-clock time, and not at all while a menu pauses the world. The
    /// interior's image space and the effect draw lists update every frame.
    private func tick(gameSession: GameSession, streamer: CellStreamer?, now: Date = Date()) {
        let renderer = gameSession.renderer
        gameSession.imageSpaceLinks?.interior = streamer?.interiorScene.map {
            InteriorImageSpace(imageSpace: $0.imageSpace, plugin: Self.basePlugin)
        }
        let paused = gameSession.worldSimPaused
        let elapsed = lastFrame.map { Float(now.timeIntervalSince($0)) } ?? 0
        let seconds = paused ? 0 : min(elapsed, Self.longestStep)
        lastFrame = paused ? nil : now
        attachRaceEffects()
        explosions.advance(seconds)
        do {
            try effects.step(seconds, extraModels: extraModels(), renderer: renderer)
        } catch {
            Self.logger.error(
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

    private static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Effects"
    )
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
        guard let gameSession = game.gameSession else { return }
        effects.startModifier(modifier, strength: strength, on: &gameSession.imageSpace)
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
    var effectCamera: VisualEffectRuntime.CameraPose? {
        game.renderer.map { .init(eye: $0.camera.eye, target: $0.camera.target) }
    }

    /// An actor's feet turned to its facing; the player's turn with the camera.
    func effectTransform(of actor: ReferenceKey) -> float4x4? {
        if actor == .player {
            guard
                let renderer = game.renderer,
                let gameSession = game.gameSession else { return nil }
            let look = renderer.camera.target - renderer.camera.eye
            return Self.transform(
                feet: gameSession.locomotion.status.feetPosition,
                yaw: atan2(look.y, look.x)
            )
        }
        guard let observed = game.actorWorld.combatActor(key: actor) else {
            // A script plays effects on objects too; they stand where their record and
            // the session's moves put them.
            return game.scripts.bridge?.referenceState(for: actor).map {
                MatrixMath.placement(
                    position: $0.transform.position, rotation: $0.transform.rotation, scale: 1
                )
            }
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
