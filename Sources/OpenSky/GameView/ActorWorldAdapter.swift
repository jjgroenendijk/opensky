// App side of `ActorValueCoordinator`: builds its runtime from the provider,
// steps regeneration on the world delta, publishes the HUD meters, and answers
// which actors are resident. The rules live in the coordinator
// (docs/engine/coordinators.md).

import Foundation
import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyCombat
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagic
import OpenSkyMenus
import OpenSkyPerceptionInterface
import OpenSkyQuests
import OpenSkyRendering
import OpenSkyWorld
import OpenSkyWorldState

/// Answers `ActorValueWorld` and the resident-actor reads from the streamer.
final class ActorWorldAdapter {
    unowned let game: GameViewController
    /// Change gate in front of the HUD meter contract.
    private var meters = HUDMeterBinding()
    /// NPC_ base raw FormID -> resolved FULL, or nil when none resolves.
    private var baseNames: [UInt32: String?] = [:]

    init(game: GameViewController) {
        self.game = game
    }

    /// A provider without stat indexes, such as every synthetic scene, leaves
    /// the runtime nil.
    func wireActorValues(provider: any WorldDataProviding, renderer: Renderer) {
        baseNames = [:]
        guard let baselines = (provider as? ActorValueDataProviding)?.actorValueBaselines
        else { return }
        let coordinator = game.actorValues
        coordinator.wire(baselines: baselines)
        // Chained after the Papyrus VM, so neither unhooks the other. The
        // renderer gates the delta, so a menu-paused frame regenerates nothing.
        let advanceScripts = renderer.onWorldUpdate
        renderer.onWorldUpdate = { [weak coordinator] delta in
            advanceScripts?(delta)
            coordinator?.advance(delta: delta)
        }
        renderer.onFrame.add { [weak self, weak renderer] _ in
            self?.publishHUDMeters(renderer: renderer)
        }
    }

    // MARK: - Resident actors

    /// Nil when nothing resident answers to `key`, such as an actor evicted
    /// mid-swing.
    func actorValueHolder(for key: ReferenceKey) -> ActorValueHolder? {
        if key == .player {
            return .player
        }
        guard let placement = game.streamer?.residentActorPlacement(key: key) else { return nil }
        return ActorValueHolder(
            key: key,
            subject: .actor(base: placement.base),
            cell: placement.cell
        )
    }

    /// Each pose is the NPC movement transform, then a stored override, then
    /// the placement.
    func combatActors() -> [CombatActorObservation] {
        guard let streamer = game.streamer else { return [] }
        let worldState = game.worldState
        return streamer.residentActorEntries().compactMap { entry in
            guard let actor = entry.placedActor else { return nil }
            let moved = streamer.npcTransform(for: entry.key)
                ?? worldState.component(ReferenceTransformOverride.self, for: entry.key)
            return CombatActorObservation(
                key: entry.key,
                feet: moved?.position ?? actor.placement.position,
                facing: moved?.rotation.z ?? actor.placement.rotation.z,
                scale: actor.scale,
                isDead: worldState.component(ActorDeathState.self, for: entry.key)?.isDead
                    ?? false,
                label: displayName(base: actor.base).map(ActorLabel.init)
                    ?? ActorLabel(key: entry.key, base: actor.base)
            )
        }
    }

    /// The FULL name of an NPC_ base after template inheritance, as the crosshair shows it.
    func displayName(base: FormID) -> String? {
        if let cached = baseNames[base.rawValue] {
            return cached
        }
        guard
            let templates = (game.worldData as? ActorValueDataProviding)?
                .actorValueBaselines?.resolver?.templates,
            let strings = game.journal.strings
        else { return nil }
        let name = (try? templates.resolveName(base: base))
            .flatMap { strings.resolve($0.value) }
            .flatMap { $0.isEmpty ? nil : $0 }
        baseNames[base.rawValue] = .some(name)
        return name
    }

    private func publishHUDMeters(renderer: Renderer?) {
        guard
            let renderer,
            game.hud.isLoaded,
            let runtime = game.actorValues.runtime,
            let meters = meters.publishing(runtime.hudMeters(for: .player))
        else { return }
        do {
            try renderer.updateSWFRuntime { runtime in
                HUDMovieBridge.setMeters(meters, runtime: runtime)
            }
        } catch {
            Self.logger.error(
                "[ERROR] HUD meters not published: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "ActorValues"
    )
}

extension ActorWorldAdapter: ActorValueWorld {
    func regeneratingHolders() -> [ActorValueHolder] {
        var holders: [ActorValueHolder] = [.player]
        guard let streamer = game.streamer else { return holders }
        for entry in streamer.residentActorEntries() {
            guard let actor = entry.placedActor else { continue }
            holders.append(ActorValueHolder(
                key: entry.key,
                subject: .actor(base: actor.base),
                cell: streamer.cellLocation(of: entry.key)
            ))
        }
        return holders
    }

    func nearestActorValueHolder() -> ActorValueHolder? {
        guard
            let streamer = game.streamer,
            let renderer = game.renderer,
            let entry = streamer.nearestActorEntry(to: renderer.freeFlyCamera.position),
            let actor = entry.placedActor
        else { return nil }
        return ActorValueHolder(
            key: entry.key,
            subject: .actor(base: actor.base),
            cell: streamer.cellLocation(of: entry.key)
        )
    }

    func isCasting(_ key: ReferenceKey) -> Bool {
        game.magic.caster?.isCasting(key) == true
    }
}
