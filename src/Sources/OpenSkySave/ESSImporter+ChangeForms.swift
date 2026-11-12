// Change forms into world state components: enable and deletion state, moves,
// inventories, quest stages, alias fills, and said dialogue. Each one that does not
// map is counted with its reason.

import Foundation
import OpenSkyDialogueInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsESS
import OpenSkyInventoryInterface
import OpenSkyQuestsInterface
import OpenSkyWorldState

nonisolated extension ESSChangeFormImport {
    func importChangeForms() {
        var aliases: [ReferenceKey: [QuestAliasFill]] = [:]
        for change in importer.file.changeForms {
            guard let type = change.type else {
                importer.report
                    .update("references") { $0.skip("change form type \(change.typeIndex)") }
                continue
            }
            switch type.signature {
            case "QUST": importQuest(change)
            case "INFO": importTopic(change)
            case "NPC_": countActorBase(change)
            default:
                if type.isReference {
                    importReference(change, aliases: &aliases)
                } else {
                    importer.report
                        .update("references") { $0.skip("\(type.signature) change forms") }
                }
            }
        }
        for (quest, fills) in aliases {
            importer.add(QuestAliasState(fills: fills), to: quest)
        }
    }

    private func importReference(
        _ change: ESSChangeForm, aliases: inout [ReferenceKey: [QuestAliasFill]]
    ) {
        let decoded: ESSReferenceChange
        do {
            decoded = try ESSReferenceChange(change)
        } catch {
            importer.report.update("references") { $0.skip("undecodable: \(error)") }
            return
        }
        let key: ReferenceKey
        switch importer.key(for: change.form) {
        case let .success(found): key = found
        case let .failure(reason):
            importer.report.update("references") { $0.drop(reason.description) }
            return
        }
        if let blocked = decoded.status.blockedBy {
            importer.report.update(decoded.isActor ? "actors" : "references") { $0.skip(blocked) }
        }
        importReferenceState(decoded, change: change, key: key)
        if let items = decoded.inventory {
            importInventory(items, key: key)
        }
        for case let .aliasInstances(instances) in decoded.extraData?.entries ?? [] {
            collectAliases(instances, key: key, into: &aliases)
        }
    }

    private func importReferenceState(
        _ decoded: ESSReferenceChange, change: ESSChangeForm, key: ReferenceKey
    ) {
        if let disabled = decoded.isDisabled, key != .player {
            importer.add(ReferenceEnableState(isEnabled: !disabled), to: key)
            if decoded.isDeleted == true {
                importer.add(ReferenceDeletionState.deleted, to: key)
            }
        }
        if decoded.isActor, change.has(ESSChangeFlag.Actor.lifeState) {
            importer.report.update("actors") { $0.skip("life state (layout undocumented)") }
        }
        let relocated = change.has(ESSChangeFlag.Reference.cellChanged)
            || change.has(ESSChangeFlag.Reference.promoted)
        guard let placement = decoded.placement, key != .player else {
            importer.report.update("references") { $0.imported += 1 }
            return
        }
        if let base = placement.createdBase {
            importSpawn(base: base, placement: placement, scale: decoded.scale, key: key)
        } else if relocated {
            importer.report.update("references") { $0.drop("moved to another cell") }
        } else {
            importer.add(
                ReferenceTransformOverride(
                    position: placement.position, rotation: placement.rotation,
                    scale: decoded.scale ?? 1
                ),
                to: key
            )
            importer.report.update("references") { $0.imported += 1 }
        }
    }

    private func importSpawn(
        base: ESSRefID, placement: ESSPlacement, scale: Float?, key: ReferenceKey
    ) {
        guard
            case let .form(baseForm) = importer.mapping.resolve(base),
            let baseID = importer.mapping.currentFormID(baseForm),
            case let .form(space) = importer.mapping.resolve(placement.space),
            let location = importer.records.cellLocation(
                space: space,
                position: placement.position
            )
        else {
            importer.report
                .update("created forms") {
                    $0.drop("created reference with an unmapped base or cell")
                }
            return
        }
        importer.add(
            ReferenceSpawnState(
                base: baseID, location: location,
                placement: PlacedReference.Placement(
                    position: placement.position, rotation: placement.rotation
                ),
                scale: scale ?? 1
            ),
            to: key
        )
        importer.report.update("created forms") { $0.imported += 1 }
    }

    /// `.ess` counts change the base container's counts, so they add to the baseline.
    private func importInventory(_ items: [ESSInventoryItem], key: ReferenceKey) {
        var counts: [FormID: Int64] = [:]
        for stack in importer.records.baselineInventory(of: key).stacks {
            counts[stack.item, default: 0] += Int64(stack.count)
        }
        var equipped: [FormID] = []
        for item in items {
            guard
                case let .form(form) = importer.mapping.resolve(item.item),
                let id = importer.mapping.currentFormID(form)
            else {
                importer.report.update("inventories") { $0.drop("item that is not a plugin form") }
                continue
            }
            counts[id, default: 0] += Int64(item.count)
            if item.isWorn {
                equipped.append(id)
            }
        }
        let stacks = counts.map { InventoryStack(item: $0.key, count: Int32(clamping: $0.value)) }
        importer.add(ReferenceInventoryState(stacks: stacks, equipped: equipped), to: key)
        importer.report.update("inventories") { category in
            category.imported += items.count
            category.skip("stolen marks (ownership extra data is not mapped)")
        }
    }

    private func collectAliases(
        _ instances: [ESSAliasInstance], key: ReferenceKey,
        into aliases: inout [ReferenceKey: [QuestAliasFill]]
    ) {
        for instance in instances {
            switch importer.form(instance.quest, signature: ["QUST"]) {
            case let .success(quest):
                aliases[ReferenceKey(resolved: quest), default: []]
                    .append(QuestAliasFill(aliasID: instance.aliasID, reference: key))
                importer.report.update("aliases") { $0.imported += 1 }
            case let .failure(reason):
                importer.report.update("aliases") { $0.drop(reason.description) }
            }
        }
    }

    private func importQuest(_ change: ESSChangeForm) {
        guard let decoded = attempt({ try ESSQuestChange(change) }) else {
            importer.report.update("quests") { $0.skip("undecodable quest change") }
            return
        }
        guard case let .success(quest) = importer.form(change.form, signature: ["QUST"]) else {
            importer.report.update("quests") { $0.drop("quest not in the current load order") }
            return
        }
        if let blocked = decoded.status.blockedBy {
            importer.report.update("quests") { $0.skip(blocked) }
        }
        let done = (decoded.stages ?? []).filter(\.isDone).compactMap { UInt16(exactly: $0.index) }
        let flags = decoded.questFlags ?? 0
        importer.add(
            QuestRuntimeState(
                isRunning: flags & 0x1 != 0, isCompleted: flags & 0x2 != 0, stagesReached: done
            ),
            to: ReferenceKey(resolved: quest)
        )
        importer.report.update("quests") { category in
            category.imported += 1
            category.skip(
                "objective states (fields unnamed)",
                count: decoded.objectives?.count ?? 0
            )
        }
    }

    private func importTopic(_ change: ESSChangeForm) {
        guard change.has(ESSChangeFlag.Topic.saidOnce) else { return }
        switch importer.form(change.form, signature: ["INFO"]) {
        case let .success(info):
            importer.add(DialogueRuntimeState(saidCount: 1), to: ReferenceKey(resolved: info))
            importer.report.update("dialogue") { $0.imported += 1 }
        case let .failure(reason):
            importer.report.update("dialogue") { $0.drop(reason.description) }
        }
    }

    /// Actor base changes other than the player's. OpenSky keeps actor state on the
    /// placed actor, so base changes are counted, not applied.
    private func countActorBase(_ change: ESSChangeForm) {
        guard change.form != ESSActorBaseChange.playerBase else { return }
        importer.report
            .update("actors") { $0.drop("actor base change (state lives on the placed actor)") }
    }
}
