import OpenSkyAIPackages
import OpenSkyConditions
import OpenSkyCrimeInterface
public import OpenSkyFactionsInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventory
public import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPerceptionInterface
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `InventoryVendorAdapter` reads from the session.
@MainActor
public protocol InventoryVendorHost: AnyObject {
    var factions: any FactionPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var inventory: any InventoryPort { get }
    var runtimeState: any RuntimeStatePort { get }
    var streamer: any CellStreamerPort { get }
    /// The faction records that resolve a `PLVD` rule's links, and the plugin they name.
    var worldRecords: (any WorldRecordsPort)? { get }
    var worldState: any WorldStateStorePort { get }
}

/// Part of `InventoryWorldAdapter`, over its own narrow host.
public struct InventoryVendorAdapter {
    public let game: any InventoryVendorHost
}

extension InventoryVendorAdapter {
    public func factionMemberships(of actor: ReferenceKey) -> ActorFactionState? {
        game.factions.memberships(of: actor)
    }

    public func residentOwner(of key: ReferenceKey) -> InventoryOwner? {
        guard let entry = game.streamer.referenceEntry(key: key) else { return nil }
        if let actor = entry.placedActor {
            return .actor(base: actor.base)
        }
        return entry.placedReference.map { .container(base: $0.base) }
    }

    public func cellLocation(of key: ReferenceKey) -> CellSceneLocation? {
        game.streamer.cellLocation(of: key)
    }

    public func itemKeywords(of item: FormID) -> [FormID]? {
        game.inventory.itemDefinitions?.definition(item)?.keywords
    }

    var hourOfDay: Float? {
        game.gameSession?.gameClock.hourOfDay
    }

    public func vendorPlaceFacts(
        of actor: ReferenceKey,
        for place: VendorPlace
    ) -> VendorPlaceFacts? {
        let streamer = game.streamer
        guard
            let placed = streamer.referenceEntry(key: actor)?.placedActor,
            let position = currentPosition(of: actor)
        else { return nil }
        let cell: ReferenceKey? = switch streamer.cellLocation(of: actor) {
        case let .interior(formID)?: recordKey(formID)
        case .exterior?, nil: nil
        }
        let target: SIMD3<Float>? = switch place {
        case let .nearReference(reference?): currentPosition(of: reference)
        case .nearEditorLocation: placed.placement.position
        case let .linkedReference(keyword):
            placed.details.linkedReferences
                .first { $0.keyword.flatMap(recordKey) == keyword }
                .flatMap { streamer.referenceEntry(formID: $0.ref)?.key }
                .flatMap(currentPosition(of:))
        default: nil
        }
        return VendorPlaceFacts(position: position, cell: cell, target: target)
    }

    public func failingVendorCondition(
        _ conditions: ConditionList, sourcePlugin _: String, merchant: ReferenceKey
    ) -> String? {
        var context = game.runtimeState.conditionContext()
        context.subject = merchant
        context.target = .player
        var evaluator = ConditionEvaluator(context: context)
        return evaluator.firstFailure(in: conditions.conditions).map(evaluator.functionName(of:))
    }

    var totalGameHours: Double? {
        game.gameSession.map { $0.gameClock.totalGameSeconds / GameClock.secondsPerHour }
    }

    var vendorRestockLedger: VendorRestockLedger {
        get { game.worldState.component(VendorRestockLedger.self, for: .player) ?? .init() }
        nonmutating set { game.worldState.set(newValue, for: .player) }
    }

    public func restockMerchantChest(_ chest: ReferenceKey) {
        for kind: WorldStateComponentKind in [.inventory, .itemCopies] {
            game.worldState.reset(kind, for: chest)
        }
    }

    /// A record link from the loaded plugin as the identity a `PLVD` rule holds.
    private func recordKey(_ formID: FormID) -> ReferenceKey? {
        guard
            let store = game.worldRecords?.factionStore,
            let plugin = game.worldRecords?.magicItemPluginName,
            let resolved = store.resolvedID(formID, fromPlugin: plugin)
        else { return nil }
        return ReferenceKey(resolved: resolved)
    }

    /// Where a loaded reference stands now: moved, or as the plugin placed it.
    private func currentPosition(of key: ReferenceKey) -> SIMD3<Float>? {
        let streamer = game.streamer
        guard let entry = streamer.referenceEntry(key: key) else {
            return nil
        }
        let moved = streamer.npcTransform(for: key)
            ?? game.worldState.component(ReferenceTransformOverride.self, for: key)
        return moved?.position
            ?? entry.placedReference?.placement.position
            ?? entry.placedActor?.placement.position
    }
}
