// Where a merchant stands, for its `PLVD` rule; its vendor conditions, run on the
// merchant; and its chest's restock. See docs/engine/vendor-factions.md.

import OpenSkyCells
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyRuntimeState
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldState
import simd

extension InventoryWorldAdapter {
    func vendorPlaceFacts(of actor: ReferenceKey, for place: VendorPlace) -> VendorPlaceFacts? {
        guard
            let streamer = game.streamer,
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

    func failingVendorCondition(
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
        set { game.worldState.set(newValue, for: .player) }
    }

    func restockMerchantChest(_ chest: ReferenceKey) {
        for kind: WorldStateComponentKind in [.inventory, .itemCopies] {
            game.worldState.reset(kind, for: chest)
        }
    }

    /// A record link from the loaded plugin as the identity a `PLVD` rule holds.
    private func recordKey(_ formID: FormID) -> ReferenceKey? {
        guard
            let store = game.worldData?.factionStore,
            let plugin = game.worldData?.magicItemPluginName,
            let resolved = store.resolvedID(formID, fromPlugin: plugin)
        else { return nil }
        return ReferenceKey(resolved: resolved)
    }

    /// Where a loaded reference stands now: moved, or as the plugin placed it.
    private func currentPosition(of key: ReferenceKey) -> SIMD3<Float>? {
        guard let streamer = game.streamer, let entry = streamer.referenceEntry(key: key) else {
            return nil
        }
        let moved = streamer.npcTransform(for: key)
            ?? game.worldState.component(ReferenceTransformOverride.self, for: key)
        return moved?.position
            ?? entry.placedReference?.placement.position
            ?? entry.placedActor?.placement.position
    }
}
