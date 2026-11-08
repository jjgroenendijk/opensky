// App side of `LockCoordinator`: puts its gate in front of every use-key press and
// answers `LockWorld` from the session systems. The rules live in the coordinator
// (docs/engine/coordinators.md, docs/engine/locks.md).

import OpenSkyActors
import OpenSkyConditions
import OpenSkyCrime
import OpenSkyDiagnostics
public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMenus
import OpenSkyPlayer
import OpenSkyProgression
public import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRendering
public import OpenSkySessionInterface
public import OpenSkyWorld
public import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `LockWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol LockWorldHost: AnyObject {
    var actorValues: any ActorValuePort { get }
    var crime: any CrimePort { get }
    var inventory: any InventoryPort { get }
    var inventoryWorld: any InventoryWorldPort { get }
    var lockpickingMenu: any LockpickingMenuPort { get }
    var perks: any PerkPort { get }
    var progression: any ProgressionPort { get }
    var streamer: (any CellStreamerPort)? { get }
    var worldState: any WorldStateStorePort { get }
}

/// Answers `LockWorld` from the session systems `game` owns.
public final class LockWorldAdapter {
    public unowned let game: any LockWorldHost

    public init(game: any LockWorldHost) {
        self.game = game
    }

    /// After `wireWorldItems`, which builds the lock coordinator.
    public func wireLocks(streamer: CellStreamer, gameSession: GameSession) {
        let renderer = gameSession.renderer
        let locks = game.inventory.locks
        let inventoryWorld = game.inventoryWorld
        streamer.activationGate.register(.lock) { [weak locks, weak inventoryWorld] target in
            locks.flatMap { inventoryWorld?.run($0.gate(target)) }
        }
        let menu = game.lockpickingMenu
        streamer.activationGate.refusals.register(.lockpicking) { [weak menu] refusal in
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
    public static let markerSize: Float = 48
    public static let markerColor = SIMD4<Float>(1, 0.85, 0.2, 1)
}

extension LockWorldAdapter: LockWorld {
    public var lockpickingSkill: Float {
        guard let index = ActorValueIdentity.index(named: "Lockpicking") else { return 0 }
        return game.actorValues.runtime?.value(at: index, on: .player) ?? 0
    }

    public var playerLevel: Int {
        game.actorValues.runtime?.baselines.playerLevel.level ?? 1
    }

    public func perkValue(
        _ value: Float, at entryPoint: PerkEntryPoint, lock: ReferenceKey, level: UInt8
    ) -> Float {
        game.perks.modified(value, at: entryPoint, on: .player, lock: lock, level: level)
    }

    public func activationFilter(of reference: ReferenceKey) -> Float {
        game.perks.modified(
            0,
            at: .filterActivation,
            on: .player,
            subjects: { _ in PerkEvaluationSubjects(owner: .player, target: reference) },
            seams: ConditionContext()
        )
    }

    public func reportSkillUse(_ use: SkillUseEvent) -> Float {
        game.progression.reportSkillUse(use)
    }

    public func reportLockpickingCrime(on lock: ReferenceKey) -> Int32 {
        game.crime.reportLockpicking(of: lock)
    }

    public func countLockPicked() {
        game.worldState.incrementMiscStat("Locks Picked")
    }

    public func lockables() -> [PlacedInteraction] {
        game.streamer?.residentInteractions.filter { $0.lock != nil } ?? []
    }

    public func itemName(_ item: FormID) -> String {
        game.inventory.name(of: item)
    }
}

extension LockWorldAdapter: LockWorldPort {}
