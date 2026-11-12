// World state entries into change forms: enable and deletion flags, moves, created
// references, inventories, quest stages, alias fills, and said dialogue. Each one that
// has no place in the save is counted with its reason.

import Foundation
import OpenSkyActorsInterface
import OpenSkyDialogueInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyFormatsESS
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkySaveInterface
import OpenSkyWorldState

nonisolated extension ESSReferenceExport {
    /// Kinds the player part writes, so the entry loop leaves them alone for the player.
    private static let playerKinds: Set<WorldStateComponentKind> = [
        .playerIdentity, .playerProgress, .spellbook, .factions, .inventory
    ]

    /// Spawns go first, so a created reference exists before its other changes.
    func exportEntries() throws(ESSExportError) {
        for entry in exporter.contents.snapshot.entries {
            entry.delta.component(ReferenceSpawnState.self).map { exportSpawn($0, key: entry.key) }
        }
        for entry in exporter.contents.snapshot.entries {
            for kind in entry.delta.sortedKinds where kind != .spawn {
                if entry.key == .player, Self.playerKinds.contains(kind) {
                    continue
                }
                try exportComponent(kind, of: entry)
            }
        }
        mergeAliasFills()
    }

    private func exportComponent(
        _ kind: WorldStateComponentKind, of entry: WorldStateSnapshotEntry
    ) throws(ESSExportError) {
        let delta = entry.delta
        switch kind {
        case .enableState:
            exportFlags(of: entry)
        case .deletion where delta.component(ReferenceEnableState.self) == nil:
            exportFlags(of: entry)
        case .deletion:
            break
        case .transform:
            delta.component(ReferenceTransformOverride.self).map { exportMove($0, key: entry.key) }
        case .inventory:
            if let inventory = delta.component(ReferenceInventoryState.self) {
                exportInventory(inventory, key: entry.key)
            }
        case .quest:
            if let quest = delta.component(QuestRuntimeState.self) {
                try exportQuest(quest, key: entry.key)
            }
        case .questAliases:
            delta.component(QuestAliasState.self).map { collectAliases($0, quest: entry.key) }
        case .dialogue:
            if let dialogue = delta.component(DialogueRuntimeState.self) {
                try exportTopic(dialogue, key: entry.key)
            }
        default:
            exporter.report.update("other state") { $0.drop("\(kind.rawValue) (no save mapping)") }
        }
    }

    // MARK: - References

    private static let placedTypes: Set = ["REFR", "ACHR"]

    /// A placed reference's change, or nil with a counted reason when the key names
    /// none the save can hold.
    private func reference(_ key: ReferenceKey) -> ESSReferenceChange? {
        if let change = exporter.references[key] {
            return change
        }
        guard let form = exporter.forms.resolved(key) else {
            exporter.report.update("references") { $0.drop("created reference with no spawn") }
            return nil
        }
        guard let ref = exporter.forms.ref(form) else {
            exporter.report.update("references") { $0.drop("reference from a plugin not loaded") }
            return nil
        }
        guard
            let signature = exporter.records.signature(of: form),
            Self.placedTypes.contains(signature)
        else {
            exporter.report.update("references") { $0.drop("not a placed reference now") }
            return nil
        }
        return ESSReferenceChange(form: ref, isActor: signature == "ACHR")
    }

    /// The plugin's flags with the session's disabled and deleted bits on top.
    private func exportFlags(of entry: WorldStateSnapshotEntry) {
        guard entry.key != .player, var change = reference(entry.key) else { return }
        let plugin = exporter.forms.resolved(entry.key)
            .flatMap { exporter.records.recordFlags(of: $0) } ?? 0
        var flags = change.formFlags ?? plugin
        if let enable = entry.delta.component(ReferenceEnableState.self) {
            let disabled = ESSReferenceChange.disabledFlag
            flags = enable.isEnabled ? flags & ~disabled : flags | disabled
        }
        if entry.delta.component(ReferenceDeletionState.self)?.isDeleted == true {
            flags |= ESSReferenceChange.deletedFlag
        }
        change.formFlags = flags
        exporter.references[entry.key] = change
        exporter.report.update("references") { $0.written += 1 }
    }

    private func exportMove(_ move: ReferenceTransformOverride, key: ReferenceKey) {
        guard key != .player, var change = reference(key) else { return }
        guard
            let form = exporter.forms.resolved(key),
            let space = exporter.records.placementSpace(of: form)
                .flatMap({ exporter.forms.ref($0) })
        else {
            exporter.report
                .update("references") { $0.drop("move of a reference with no known cell") }
            return
        }
        change.placement = ESSPlacement(
            space: space, position: move.position, rotation: move.rotation
        )
        change.scale = move.scale == 1 ? change.scale : move.scale
        exporter.references[key] = change
        exporter.report.update("references") { $0.written += 1 }
    }

    private func exportSpawn(_ spawn: ReferenceSpawnState, key: ReferenceKey) {
        guard
            let ref = exporter.forms.ref(key), ref.kind == .created,
            let base = exporter.forms.ref(loadOrder: spawn.base),
            let space = spawnSpace(spawn.location)
        else {
            exporter.report
                .update("created forms") { $0.drop("created reference with no base or cell") }
            return
        }
        var change = exporter.references[key] ?? ESSReferenceChange(form: ref, isActor: false)
        change.placement = ESSPlacement(
            space: space, position: spawn.placement.position,
            rotation: spawn.placement.rotation, createdBase: base
        )
        change.scale = spawn.scale == 1 ? nil : spawn.scale
        exporter.references[key] = change
        exporter.report.update("created forms") { category in
            category.written += 1
            if spawn.count != 1 {
                category.drop("stack count of a created reference")
            }
        }
    }

    /// An interior's cell, or the player's worldspace for an exterior: OpenSky keeps
    /// no worldspace per created reference.
    private func spawnSpace(_ location: CellSceneLocation) -> ESSRefID? {
        switch location {
        case let .interior(cell): exporter.forms.ref(loadOrder: cell)
        case .exterior: exporter.playerWorldspace
        }
    }

    private func exportInventory(
        _ inventory: ReferenceInventoryState, key: ReferenceKey
    ) {
        guard var change = reference(key) else { return }
        change.inventory = inventoryChanges(inventory, key: key)
        exporter.references[key] = change
    }

    /// The save stores each item's change to the base container, with worn items marked.
    func inventoryChanges(
        _ inventory: ReferenceInventoryState, key: ReferenceKey
    ) -> [ESSInventoryItem] {
        var counts: [FormID: Int64] = [:]
        for stack in inventory.stacks {
            counts[stack.item, default: 0] += Int64(stack.count)
        }
        for stack in exporter.records.baselineInventory(of: key).stacks {
            counts[stack.item, default: 0] -= Int64(stack.count)
        }
        let worn = Set(inventory.equipped)
        var items: [ESSInventoryItem] = []
        for (item, count) in counts.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            guard count != 0 || worn.contains(item) else { continue }
            guard let ref = exporter.forms.ref(loadOrder: item) else {
                exporter.report.update("inventories") { $0.drop("item from a plugin not loaded") }
                continue
            }
            let extra = worn.contains(item) ? [ESSExtraDataList(entries: [.worn])] : []
            items.append(
                ESSInventoryItem(item: ref, count: Int32(clamping: count), extraData: extra)
            )
        }
        exporter.report.update("inventories") { category in
            category.written += items.count
            category.drop(
                "stolen marks (ownership extra data is not written)",
                count: inventory.stacks.filter(\.stolen).count
            )
        }
        return items
    }

    // MARK: - Quests, aliases, and dialogue

    private func exportQuest(
        _ quest: QuestRuntimeState, key: ReferenceKey
    ) throws(ESSExportError) {
        guard
            let form = exporter.forms.resolved(key), exporter.records.signature(of: form) == "QUST",
            let ref = exporter.forms.ref(form)
        else {
            exporter.report.update("quests") { $0.drop("quest from a plugin not loaded") }
            return
        }
        var change = ESSQuestChange(form: ref)
        change.questFlags = (quest.isRunning ? 0x1 : 0) | (quest.isCompleted ? 0x2 : 0)
        let stages = quest.stagesReached.compactMap(Int16.init(exactly:))
        change.stages = stages.map { ESSQuestStage(index: $0, isDone: true) }
        try exporter.changeForms
            .append(ESSExporter.encode { () throws(ESSError) in try change.changeForm() })
        exporter.report.update("quests") { category in
            category.written += 1
            category.drop("objective states (fields unnamed)", count: quest.objectives.count)
            category.drop("stage above 32767", count: quest.stagesReached.count - stages.count)
        }
    }

    private func collectAliases(_ state: QuestAliasState, quest: ReferenceKey) {
        guard
            let form = exporter.forms.resolved(quest),
            let questRef = exporter.forms.ref(form)
        else {
            exporter.report.update("aliases") { $0.drop("quest from a plugin not loaded") }
            return
        }
        for fill in state.fills {
            exporter.aliasFills[fill.reference, default: []]
                .append(ESSAliasInstance(quest: questRef, aliasID: fill.aliasID))
        }
        exporter.report.update("aliases") { category in
            category.drop("location alias fills", count: state.locationFills.count)
        }
    }

    /// Alias instances live in the filled reference's extra data.
    private func mergeAliasFills() {
        for key in exporter.aliasFills.keys.sorted() {
            guard let instances = exporter.aliasFills[key], var change = reference(key) else {
                exporter.report.update("aliases") { $0.drop("filled reference not in the save") }
                continue
            }
            change.extraData = ESSExtraDataList(entries: [.aliasInstances(instances)])
            exporter.references[key] = change
            exporter.report.update("aliases") { $0.written += instances.count }
        }
    }

    private func exportTopic(
        _ dialogue: DialogueRuntimeState, key: ReferenceKey
    ) throws(ESSExportError) {
        guard dialogue.hasBeenSaid else { return }
        guard
            let form = exporter.forms.resolved(key), exporter.records.signature(of: form) == "INFO",
            let ref = exporter.forms.ref(form)
        else {
            exporter.report.update("dialogue") { $0.drop("topic info from a plugin not loaded") }
            return
        }
        let change = ESSTopicChange(form: ref, saidOnce: true)
        try exporter.changeForms
            .append(ESSExporter.encode { () throws(ESSError) in try change.changeForm() })
        exporter.report.update("dialogue") { category in
            category.written += 1
            category.drop("speaker reset days", count: dialogue.saidDays.count)
        }
    }
}
