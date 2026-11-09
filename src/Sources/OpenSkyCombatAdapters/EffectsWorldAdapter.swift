// App side of visual and audio effects: hands the load-order effect records
// to the image-space resolve, the explosion runtime, and the effects
// coordinator; routes spell hits; and steps debris and effects each frame.
// The rules live in the coordinators (docs/rendering/visual-effects.md).

import Foundation
import OpenSkyActorPresentation
import OpenSkyActorsInterface
public import OpenSkyCells
public import OpenSkyCombat
import OpenSkyCombatInterface
public import OpenSkyEffects
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `EffectsWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol EffectsWorldHost: AnyObject {
    var combat: any CombatPort { get }
    var effects: any EffectsPort { get }
    var playerSettings: any PlayerSettingsPort { get }
    var worldData: WorldDataStores? { get }
    var hazardWorld: any HazardWorldPort { get }
    var hazards: any HazardPort { get }
    var magic: any MagicPort { get }
    var ragdoll: any RagdollPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var streamer: (any CellStreamerPort)? { get }
}

public final class EffectsWorldAdapter {
    /// A long frame steps as this, as for hazards.
    public static let longestStep: Float = 0.25
    // Base plugin of the streamed cells and the item and sound indexes.

    public let game: any EffectsWorldHost
    public let state = EffectsPartState()
    /// Actors whose race abilities were looked at, so each is resolved once.
    private var raceChecked: Set<ReferenceKey> = []
    private var lastFrame: Date?

    public let bodyImpulsesHost: any EffectsBodyImpulsesHost
    public let locatorHost: any EffectsLocatorHost
    public let trapControlHost: any EffectsTrapControlHost
    public let blastsHost: any EffectsBlastsHost
    public let effectPlacementHost: any EffectsEffectPlacementHost

    public var bodyImpulses: EffectsBodyImpulsesAdapter {
        EffectsBodyImpulsesAdapter(game: bodyImpulsesHost, effects: effects, locator: locator)
    }

    public var locator: EffectsLocatorAdapter {
        EffectsLocatorAdapter(game: locatorHost)
    }

    public var trapControl: EffectsTrapControlAdapter {
        EffectsTrapControlAdapter(
            game: trapControlHost, state: state, bodyImpulses: bodyImpulses, locator: locator
        )
    }

    public var blasts: EffectsBlastsAdapter {
        EffectsBlastsAdapter(game: blastsHost, state: state)
    }

    public var effectPlacement: EffectsEffectPlacementAdapter {
        EffectsEffectPlacementAdapter(game: effectPlacementHost, state: state)
    }

    public init(game: some EffectsWorldHost & EffectsBodyImpulsesHost & EffectsTrapControlHost &
        EffectsBlastsHost & EffectsEffectPlacementHost & EffectsLocatorHost)
    {
        bodyImpulsesHost = game
        locatorHost = game
        trapControlHost = game
        blastsHost = game
        effectPlacementHost = game
        self.game = game
    }

    public var effects: any EffectsPort {
        game.effects
    }

    public func nextHazardKey() -> ReferenceKey {
        state.nextHazardKey()
    }

    public var explosions: any ExplosionRuntimePort {
        game.combat.explosions
    }

    /// The visual, image-space, and sound side of one landed spell.
    public func handleSpellHit(_ event: SpellHitEvent) {
        guard let gameSession = game.gameSession else { return }
        effects.handleSpellHit(event, imageSpace: &gameSession.imageSpace)
        effects.detonateAreaExplosions(of: event)
        noteSpellHit(event.hit)
        playHitSounds(of: event, director: gameSession.soundDirector)
    }

    /// The explosion runtime the combat coordinator owns. Without effect records it
    /// has no world, and nothing detonates.
    public func makeExplosions() -> ExplosionRuntime {
        guard let records = game.worldData?.effectRecords else { return ExplosionRuntime() }
        let explosions = ExplosionRuntime(
            records: records,
            itemPlugin: EffectsBasePlugin.name,
            world: self
        )
        explosions.impulses = bodyImpulses.makeImpulses(world: self)
        return explosions
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
    private func playHitSounds(
        of event: SpellHitEvent,
        director: (any WorldAudioSoundDirectorPort)?
    ) {
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
    public static func meshes(
        provider: WorldDataStores,
        renderer: Renderer
    ) -> MeshLibrary? {
        guard
            let fileSystem = provider.scriptFileSystem,
            let textures = attempt({ try TextureLibrary(
                fileSystem: fileSystem,
                device: renderer.device
            ) })
        else { return nil }
        return MeshLibrary(fileSystem: fileSystem, device: renderer.device, textures: textures)
    }

    /// Steps by wall-clock time, and not at all while a menu pauses the world. The
    /// interior's image space and the effect draw lists update every frame.
    func tick(gameSession: GameSession, streamer: CellStreamer?, now: Date = Date()) {
        let renderer = gameSession.renderer
        gameSession.imageSpaceLinks?.interior = streamer?.interiorScene.map {
            InteriorImageSpace(imageSpace: $0.imageSpace, plugin: EffectsBasePlugin.name)
        }
        let paused = gameSession.worldSimPaused
        let elapsed = lastFrame.map { Float(now.timeIntervalSince($0)) } ?? 0
        let seconds = paused ? 0 : min(elapsed, Self.longestStep)
        lastFrame = paused ? nil : now
        attachRaceEffects()
        explosions.advance(seconds)
        effectPlacement.stepHealthCues(seconds, gameSession: gameSession)
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
                guard let path = game.hazardWorld.hazardModelPath(for: hazard.spec.hazard) else {
                    return nil
                }
                var transform = matrix_identity_float4x4
                transform.columns.3 = SIMD4(hazard.position, 1)
                return VisualEffectModel(path: path, transform: transform)
            }
        return debris + hazards + blasts.projectileModels()
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

    private static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Effects"
    )
}

extension EffectsWorldAdapter: ExplosionWorld {}

extension EffectsWorldAdapter: EffectsWorld {}

extension EffectsWorldAdapter: EffectsWorldPort {}
