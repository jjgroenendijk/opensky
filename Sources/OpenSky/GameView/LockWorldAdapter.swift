// App side of `LockCoordinator`: puts its gate in front of every use-key press and
// answers `LockWorld` from the session systems. The rules live in the coordinator
// (docs/engine/coordinators.md, docs/engine/locks.md).

import OpenSkyActors
import OpenSkyDiagnostics
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyRendering
import OpenSkyWorld
import OpenSkyWorldInterface

/// Answers `LockWorld` from the session systems `game` owns.
final class LockWorldAdapter {
    unowned let game: GameViewController

    init(game: GameViewController) {
        self.game = game
    }

    /// After `wireWorldItems`, which wires the coordinator's item runtime.
    func wireLocks(provider: any WorldDataProviding, streamer: CellStreamer, renderer: Renderer) {
        let locks = game.inventory.locks
        locks.world = self
        if let data = (provider as? LockTrapDataProviding)?.lockTrapData {
            locks.settings = data.lockpicking
            locks.lockpickItem = data.lockpickItem
        }
        streamer.activationGate.gate = { [weak locks] target in
            locks?.gate(target)
        }
        let menu = game.lockpickingMenu
        streamer.activationGate.refusals.add { [weak menu] refusal in
            menu?.handle(refusal)
        }
        // `onFrame` runs while the menu pauses the world; the menu keeps its own clock.
        renderer.onFrame.add { [weak menu] _ in
            menu?.tick()
        }
        renderer.worldOverlaySources
            .register(identifier: "lock-selection") { [weak locks] _, list in
                guard let position = locks?.selectedInteraction?.position else { return }
                list.addMarker(at: position, size: Self.markerSize, color: Self.markerColor)
            }
    }

    /// The selected lock's marker: yellow, about a door's half width.
    static let markerSize: Float = 48
    static let markerColor = SIMD4<Float>(1, 0.85, 0.2, 1)
}

extension LockWorldAdapter: LockWorld {
    var lockpickingSkill: Float {
        guard let index = ActorValueIdentity.index(named: "Lockpicking") else { return 0 }
        return game.actorValues.runtime?.value(at: index, on: .player) ?? 0
    }

    func perkValue(
        _ value: Float, at entryPoint: PerkEntryPoint, lock: ReferenceKey, level: UInt8
    ) -> Float {
        game.perks.modified(value, at: entryPoint, on: .player, lock: lock, level: level)
    }

    func reportSkillUse(_ use: SkillUseEvent) -> Float {
        game.progression.reportSkillUse(use)
    }

    func lockStateChanged() {
        game.inventoryWorld.refreshInteractionTarget()
    }

    func lockables() -> [PlacedInteraction] {
        game.streamer?.residentInteractions.filter { $0.lock != nil } ?? []
    }

    func itemName(_ item: FormID) -> String {
        game.inventory.name(of: item)
    }
}
