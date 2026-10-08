// Game events for `openskycli game events`. Cell and activation events come
// from streamer callbacks. Menus, deaths, quest stages, hits, and script
// faults come from comparing state between polls. Error and fault log lines
// come from `EngineLogTap`.

import Foundation
import OpenSkyActorsInterface
import OpenSkyAgentControl
import OpenSkyCombat
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyQuests
import OpenSkyQuestsInterface
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

struct AgentEventTapState {
    static let pendingLimit = 512

    var wired = false
    var seeded = false
    var pending: [(String, [String: AgentJSON])] = []
    var menus: [String] = []
    var dead: Set<ReferenceKey> = []
    var questStages: [String: UInt16] = [:]
    var hitCount = 0
    var scriptTick = 0
    var nextSlowPoll = 0.0

    mutating func append(_ kind: String, _ data: [String: AgentJSON]) {
        pending.append((kind, data))
        if pending.count > Self.pendingLimit {
            pending.removeFirst(pending.count - Self.pendingLimit)
        }
    }
}

extension AgentWorldAdapter {
    static let slowPollSeconds = 0.25

    func pollEvents(_ emit: (String, [String: AgentJSON]) -> Void) {
        wireEventCallbacks()
        diffMenus()
        let now = ProcessInfo.processInfo.systemUptime
        if now >= tap.nextSlowPoll {
            tap.nextSlowPoll = now + Self.slowPollSeconds
            diffDeaths()
            diffQuestStages()
            diffCombatAndScripts()
            tap.seeded = true
        }
        for line in EngineLogTap.drain() {
            tap.append(AgentEventKind.log, [
                "category": .string(line.category), "message": .string(line.message)
            ])
        }
        for (kind, data) in tap.pending {
            emit(kind, data)
        }
        tap.pending.removeAll()
    }

    private func wireEventCallbacks() {
        guard !tap.wired, let streamer = game.streamer else { return }
        tap.wired = true
        let attached = streamer.onCellAttached
        streamer.onCellAttached = { [weak self] scene, first in
            attached?(scene, first)
            // A rebuild of the same cell after a state change is not a new load.
            guard first else { return }
            self?.tap.append(AgentEventKind.cellLoaded, Self.cellData(scene))
        }
        let detached = streamer.onCellDetached
        streamer.onCellDetached = { [weak self] location in
            detached?(location)
            self?.tap.append(AgentEventKind.cellUnloaded, Self.locationData(location))
        }
        streamer.onInteraction.add { [weak self] event in
            self?.tap.append(
                AgentEventKind.activation,
                Self.interactionData(event.target.interaction)
            )
        }
        streamer.activationGate.refusals.add { [weak self] event in
            var data = Self.interactionData(event.target.interaction)
            if case let .locked(level, _) = event.refusal {
                data["reason"] = "locked"
                data["lockLevel"] = .init(Int(level))
            }
            self?.tap.append(AgentEventKind.activationRefused, data)
        }
    }

    private static func cellData(_ scene: CellScene) -> [String: AgentJSON] {
        var data = scene.location.map(locationData) ?? [:]
        data["name"] = .string(scene.summary.cellName)
        return data
    }

    private static func locationData(_ location: CellSceneLocation) -> [String: AgentJSON] {
        switch location {
        case let .exterior(grid):
            ["interior": false, "x": .init(Int(grid.x)), "y": .init(Int(grid.y))]
        case let .interior(cell):
            ["interior": true, "cell": .formID(cell.rawValue)]
        }
    }

    private static func interactionData(_ interaction: PlacedInteraction) -> [String: AgentJSON] {
        [
            "ref": .formID(interaction.reference.rawValue), "name": .string(interaction.name),
            "action": .string(interaction.actionLabel)
        ]
    }

    private func diffMenus() {
        let menus = game.menuMode.stack.identifiers.map(\.name)
        guard menus != tap.menus else { return }
        for name in tap.menus where !menus.contains(name) {
            tap.append(AgentEventKind.menuClosed, ["menu": .string(name)])
        }
        for name in menus where !tap.menus.contains(name) {
            tap.append(AgentEventKind.menuOpened, ["menu": .string(name)])
        }
        tap.menus = menus
    }

    private func diffDeaths() {
        guard let streamer = game.streamer else { return }
        for entry in streamer.residentActorEntries() {
            let isDead = game.worldState.component(ActorDeathState.self, for: entry.key)?
                .isDead ?? false
            guard isDead, !tap.dead.contains(entry.key) else { continue }
            tap.dead.insert(entry.key)
            guard tap.seeded else { continue }
            tap.append(AgentEventKind.actorDeath, [
                "ref": .formID(entry.formID.rawValue),
                "name": .string(game.dialogueWorld.speakerLabel(for: entry.key))
            ])
        }
    }

    private func diffQuestStages() {
        guard let quests = game.journalMenu.questRuntime else { return }
        for (quest, state) in quests.runtimeQuests() {
            guard
                let editorID = quest.editorID,
                let stage = state.stagesReached.last else { continue }
            guard tap.questStages[editorID] != stage else { continue }
            tap.questStages[editorID] = stage
            guard tap.seeded else { continue }
            tap.append(
                AgentEventKind.questStage,
                ["id": .string(editorID), "stage": .init(Int(stage))]
            )
        }
    }

    private func diffCombatAndScripts() {
        let melee = game.meleeCombatSnapshot
        if melee.hitCount > tap.hitCount, tap.seeded, let hit = melee.trace.last {
            tap.append(AgentEventKind.combatHit, [
                "target": .string(hit.target), "damage": .init(hit.appliedDamage)
            ])
        }
        tap.hitCount = melee.hitCount
        let scripts = game.scripts.scriptsSnapshot
        if scripts.tickCount != tap.scriptTick, scripts.lastTickFaulted > 0, tap.seeded {
            tap.append(AgentEventKind.scriptError, [
                "faulted": .init(scripts.lastTickFaulted), "tick": .init(scripts.tickCount),
                "fault": .init(scripts.lastFault)
            ])
        }
        tap.scriptTick = scripts.tickCount
    }
}
