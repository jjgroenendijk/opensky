// App side of visual and audio effects: hands the load-order effect records
// to the image-space resolve, the explosion runtime, and the effects
// coordinator; routes spell hits; and steps debris and effects each frame.
// The rules live in the coordinators (docs/rendering/visual-effects.md).

public import Foundation
import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyCells
public import OpenSkyCombat
public import OpenSkyCombatInterface
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
public protocol EffectsWorldHost: AnyObject, SendableMetatype {
    var combat: any CombatPort { get }
    var effects: any EffectsPort { get }
    var combatRecords: (any CombatRecordsPort)? { get }
    var hazardWorld: any HazardWorldPort { get }
    var hazards: any HazardPort { get }
    var magic: any MagicPort { get }
    var ragdoll: any RagdollPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var streamer: any CellStreamerPort { get }
}

public final class EffectsWorldAdapter {
    /// A long frame steps as this, as for hazards.
    static let longestStep: Float = 0.25
    // Base plugin of the streamed cells and the item and sound indexes.

    public let game: any EffectsWorldHost
    public let state = EffectsPartState()
    lazy var frameLooks = EffectsFrameLooks(game: game, blastsHost: blastsHost, state: state)
    var lastFrame: Date?
    let now: () -> Date

    public let bodyImpulsesHost: any EffectsBodyImpulsesHost
    public let locatorHost: any EffectsLocatorHost
    public let trapControlHost: any EffectsTrapControlHost
    public let blastsHost: any EffectsBlastsHost
    public let effectPlacementHost: any EffectsEffectPlacementHost

    public var bodyImpulses: EffectsBodyImpulsesAdapter {
        EffectsBodyImpulsesAdapter(game: bodyImpulsesHost, effects: effects, locator: locator)
    }

    var locator: EffectsLocatorAdapter {
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

    public init(
        game: some EffectsWorldHost & EffectsBodyImpulsesHost & EffectsTrapControlHost &
            EffectsBlastsHost & EffectsEffectPlacementHost & EffectsLocatorHost,
        now: @escaping () -> Date
    ) {
        self.now = now
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

    var explosions: any ExplosionRuntimePort {
        game.combat.explosions
    }

    /// The visual, image-space, and sound side of one landed spell.
    public func handleSpellHit(_ event: SpellHitEvent) {
        spellHits.handleSpellHit(event)
    }

    /// The explosion runtime the combat coordinator owns. Without effect records it
    /// has no world, and nothing detonates.
    public func makeExplosions() -> ExplosionRuntime {
        guard let records = game.combatRecords?.effectRecords else { return ExplosionRuntime() }
        let explosions = ExplosionRuntime(
            records: records,
            itemPlugin: EffectsBasePlugin.name,
            world: self
        )
        explosions.impulses = bodyImpulses.makeImpulses(world: self)
        return explosions
    }
}

extension EffectsWorldAdapter: ExplosionWorld {}

extension EffectsWorldAdapter: EffectsWorld {}

extension EffectsWorldAdapter: EffectsWorldPort {}

/// The spell-hit side of `EffectsWorldAdapter`: ragdoll notes and hit sounds.
struct EffectsSpellHits {
    let game: any EffectsWorldHost
    let effects: any EffectsPort
    let effectPlacement: EffectsEffectPlacementAdapter

    func handleSpellHit(_ event: SpellHitEvent) {
        guard let gameSession = game.gameSession else { return }
        effects.handleSpellHit(event, imageSpace: &gameSession.imageSpace)
        effects.detonateAreaExplosions(of: event)
        noteSpellHit(event.hit)
        playHitSounds(of: event, director: gameSession.soundDirector)
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
                guard let transform = effectPlacement.effectTransform(of: target.key)
                else { continue }
                let origin = transform.columns.3
                director.forcePlaySound(
                    formID: sound,
                    position: SIMD3(origin.x, origin.y, origin.z)
                )
            }
        }
    }
}

/// The race-ability looks and the extra models of the effects frame step.
final class EffectsFrameLooks {
    let game: any EffectsWorldHost
    let blastsHost: any EffectsBlastsHost
    let state: EffectsPartState
    /// Actors whose race abilities were looked at, so each is resolved once.
    var raceChecked: Set<ReferenceKey> = []

    init(game: any EffectsWorldHost, blastsHost: any EffectsBlastsHost, state: EffectsPartState) {
        self.game = game
        self.blastsHost = blastsHost
        self.state = state
    }

    var effects: any EffectsPort {
        game.effects
    }

    var explosions: any ExplosionRuntimePort {
        game.combat.explosions
    }

    var blasts: EffectsBlastsAdapter {
        EffectsBlastsAdapter(game: blastsHost, state: state)
    }

    /// Debris pieces and the models of spawned hazards, drawn beside the effects.
    func extraModels() -> [VisualEffectModel] {
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
    func attachRaceEffects() {
        let resident = game.streamer.residentActorEntries()
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
}

/// The main-thread mesh library of the effects coordinator.
public enum EffectsMeshes {
    /// A main-thread library of its own: the cell build queue owns the other one.
    public static func meshes(
        provider: any CombatRecordsPort,
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
}

extension EffectsWorldAdapter {
    var spellHits: EffectsSpellHits {
        EffectsSpellHits(game: game, effects: effects, effectPlacement: effectPlacement)
    }
}
