import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyAudio
public import OpenSkyBehavior
public import OpenSkyCells
public import OpenSkyCombat
public import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyDialogueInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyNavigation
import OpenSkyPerceptionInterface
public import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
public import OpenSkyWorldState
import simd

/// What `CombatMotionAdapter` reads from the session.
@MainActor
public protocol CombatMotionHost: AnyObject {
    var actorGraphs: any ActorGraphPort { get }
    var aiWorld: any AIWorldPort { get }
    var audio: any AudioPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var packages: any PackagePort { get }
    var ragdoll: any RagdollPort { get }
    var streamer: (any CellStreamerPort)? { get }
    var worldData: WorldDataStores? { get }
    var worldState: any WorldStateStorePort { get }
}

/// Part of `CombatWorldAdapter`, over its own narrow host.
public struct CombatMotionAdapter {
    public let game: any CombatMotionHost
    public let impactEffects: CombatImpactEffectsAdapter
}

extension CombatMotionAdapter {
    /// An actor whose AI a script turned off does not fight either.
    public func packageIgnoresCombat(_ key: ReferenceKey) -> Bool {
        game.packages.ignoresCombat(key) || game.aiWorld.isAIDisabled(key)
    }

    public func isKnockedDown(_ key: ReferenceKey) -> Bool {
        game.ragdoll.knockdowns.isKnockedDown(key)
    }

    @discardableResult
    public func moveActor(_ key: ReferenceKey, to point: SIMD3<Float>) -> Bool {
        game.streamer?.moveActor(key, to: point) == .started
    }

    @discardableResult
    public func moveActor(
        _ key: ReferenceKey,
        to point: SIMD3<Float>,
        gait: LocomotionGait?
    ) -> Bool {
        game.streamer?.moveActor(key, to: point, direct: false, gait: gait) == .started
    }

    public func faceActor(_ key: ReferenceKey, toward point: SIMD3<Float>) {
        _ = game.streamer?.faceActor(key, towards: point)
    }

    public func stopActor(_ key: ReferenceKey) {
        game.streamer?.stopActor(key)
    }

    public func resumePackage(for key: ReferenceKey) {
        game.packages.resume(key)
    }

    /// True when the graph declared a home for the event, which is the graph's
    /// own answer rather than an assumption.
    @discardableResult
    public func raisePlayerGraphEvent(_ name: String) -> Bool {
        guard let gameSession = game.gameSession else { return false }
        gameSession.locomotion.raise(name)
        return gameSession.locomotion.status.raisedEvents.contains(name)
    }

    public func writePlayerGraphVariable(_ value: BehaviorVariableValue, named name: String) {
        game.gameSession?.locomotion.write(value, to: name)
    }

    @discardableResult
    public func raiseActorGraphEvent(_ name: String, on key: ReferenceKey) -> Bool {
        game.actorGraphs.raise(name, on: key)
    }

    public func writeActorGraphVariable(
        _ value: BehaviorVariableValue, named name: String, on key: ReferenceKey
    ) {
        game.actorGraphs.setVariable(value, named: name, on: key)
    }

    public func recordHealthHit(_ hit: CombatHitRecord, on key: ReferenceKey) {
        game.ragdoll.noteHit(hit, on: key)
    }

    /// A playback failure is logged by the engine and leaves the hit silent. The
    /// file loads off the main actor and is kept, so a repeated impact does not read it.
    public func playImpact(_ impact: ResolvedMeleeImpact, at position: SIMD3<Float>) {
        playImpact(impact, at: position, gain: 1)
    }

    public func playImpact(_ impact: ResolvedMeleeImpact, at position: SIMD3<Float>, gain: Float) {
        impactEffects.showImpact(impact, at: position)
        guard
            let engine = game.gameSession?.worldAudio, engine.isRunning,
            let assets = game.audio.assets,
            let sounds = game.worldData?.soundStore,
            let sound = attempt({ try sounds.resolveAny(impact.sound) }),
            let path = sound.filePaths.first
        else { return }
        let request = AudioPlayRequest(
            name: path, category: sound.audioCategory ?? .footsteps, worldPosition: position,
            gain: gain, soundCategory: sound.descriptor.category
        )
        assets.request(path) { result in
            _ = attempt { try engine.playPositional(asset: result.get(), request: request) }
        }
    }

    public func sweep(_ query: ShapeSweepQuery) -> ShapeSweepHit? {
        guard let streamer = game.streamer else { return nil }
        return ShapeSweeper.firstHit(
            query: query,
            shapes: streamer.staticCollisionCandidates(overlapping: query.bounds)
        )
    }

    public func residentCells() -> Set<CellSceneLocation> {
        guard let streamer = game.streamer else { return [] }
        if let interior = streamer.interiorScene?.location {
            return [interior]
        }
        return Set(streamer.composition.cells.values.compactMap(\.location))
    }

    public func spawn(
        _ reference: ReferenceSpawnState,
        in location: CellSceneLocation
    ) -> ReferenceKey? {
        let key = game.worldState.allocateGeneratedKey()
        game.worldState.set(reference, for: key, in: location)
        return key
    }

    /// Dropping the whole delta, as `WorldItemRuntime.removeFromWorld` does,
    /// leaves nothing of a spawned object in the next save.
    public var bodyTransients: CombatTransientCounts {
        CombatTransientCounts(
            activeRagdolls: game.ragdoll.runtime?.world.ragdollCount ?? 0,
            awakeBodies: game.streamer?.dynamicBodies.activeBodyCount ?? 0
        )
    }

    public func trimBodyTransients(to limits: CombatTransientLimits) -> CombatTransientCounts {
        CombatTransientCounts(
            activeRagdolls: game.ragdoll.runtime?.trim(to: limits.activeRagdolls) ?? 0,
            awakeBodies: game.streamer?.dynamicBodies.sleepExcessBodies(over: limits.awakeBodies)
                ?? 0
        )
    }
}
