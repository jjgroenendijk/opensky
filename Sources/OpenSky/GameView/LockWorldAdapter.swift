// App side of `LockCoordinator`: puts its gate in front of every use-key press and
// answers `LockWorld` from the session systems. The rules live in the coordinator
// (docs/engine/coordinators.md, docs/engine/locks.md).

import OpenSkyActors
import OpenSkyCells
import OpenSkyConditions
import OpenSkyDiagnostics
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMenus
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyRendering
import OpenSkyWorld
import OpenSkyWorldInterface

/// What `LockWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
protocol LockWorldHost: AnyObject {
    var actorValues: ActorValueCoordinator { get }
    var hud: HUDCoordinator { get }
    var inventory: InventoryCoordinator { get }
    var inventoryWorld: InventoryWorldAdapter { get }
    var lockpickingMenu: LockpickingMenuController { get }
    var mapWorld: MapWorldAdapter { get }
    var perks: PerkCoordinator { get }
    var progression: ProgressionCoordinator { get }
    var streamer: CellStreamer? { get }
}

/// Answers `LockWorld` from the session systems `game` owns.
final class LockWorldAdapter {
    unowned let game: any LockWorldHost

    init(game: any LockWorldHost) {
        self.game = game
    }

    /// After `wireWorldItems`, which wires the coordinator's item runtime.
    func wireLocks(provider: WorldDataStores, streamer: CellStreamer, gameSession: GameSession) {
        let renderer = gameSession.renderer
        let locks = game.inventory.locks
        locks.settings = provider.lockTrapData.lockpicking
        locks.lockpickItem = provider.lockTrapData.lockpickItem
        locks.texts = LockTexts
            .resolve(store: provider.gameSettings) { [game] in game.mapWorld.text($0) }
        let inventoryWorld = game.inventoryWorld
        streamer.activationGate.gate = { [weak locks, weak inventoryWorld] target in
            locks.flatMap { inventoryWorld?.run($0.gate(target)) }
        }
        let menu = game.lockpickingMenu
        streamer.activationGate.refusals.add { [weak menu] refusal in
            menu?.handle(refusal)
        }
        // Frame steps run while the menu pauses the world; the menu keeps its own clock.
        gameSession.frameSteps.register(.lockpicking) { [weak menu] _ in
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

    func activationFilter(of reference: ReferenceKey) -> Float {
        game.perks.modified(
            0,
            at: .filterActivation,
            on: .player,
            subjects: { _ in PerkEvaluationSubjects(owner: .player, target: reference) },
            seams: ConditionContext()
        )
    }

    func reportSkillUse(_ use: SkillUseEvent) -> Float {
        game.progression.reportSkillUse(use)
    }

    func lockables() -> [PlacedInteraction] {
        game.streamer?.residentInteractions.filter { $0.lock != nil } ?? []
    }

    func itemName(_ item: FormID) -> String {
        game.inventory.name(of: item)
    }
}
