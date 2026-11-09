import Foundation
import OpenSkyActorsInterface
public import OpenSkyAgentControl
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyEffects
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyLoading
import OpenSkyMenusInterface
import OpenSkyObjectAnimation
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkySaveInterface
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWeather
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

public struct AgentEventTapState {
    public static let pendingLimit = 512

    public var wired = false
    public var seeded = false
    public var pending: [(String, [String: AgentJSON])] = []
    public var menus: [String] = []
    public var dead: Set<ReferenceKey> = []
    public var questStages: [String: UInt16] = [:]
    public var hitCount = 0
    public var scriptTick = 0
    public var nextSlowPoll = 0.0

    public mutating func append(_ kind: String, _ data: [String: AgentJSON]) {
        pending.append((kind, data))
        if pending.count > Self.pendingLimit {
            pending.removeFirst(pending.count - Self.pendingLimit)
        }
    }
}

/// What `AgentEventsAdapter` reads from the session.
@MainActor
public protocol AgentEventsHost: AnyObject {
    var combat: any CombatPort { get }
    var dialogueWorld: any DialogueWorldPort { get }
    var journalMenu: any JournalMenuPort { get }
    var menuMode: any MenuModePort { get }
    var scripts: any ScriptPort { get }
    var streamer: any CellStreamerPort { get }
    var worldState: any WorldStateStorePort { get }
}

/// Part of `AgentWorldAdapter`, over its own narrow host.
public struct AgentEventsAdapter {
    public let hub: AgentHub
    public let game: any AgentEventsHost
}

extension AgentEventsAdapter {
    public static let slowPollSeconds = 0.25

    public func pollEvents(_ emit: (String, [String: AgentJSON]) -> Void) {
        wireEventCallbacks()
        diffMenus()
        let now = ProcessInfo.processInfo.systemUptime
        if now >= hub.tap.nextSlowPoll {
            hub.tap.nextSlowPoll = now + Self.slowPollSeconds
            diffDeaths()
            diffQuestStages()
            diffCombatAndScripts()
            hub.tap.seeded = true
        }
        for line in EngineLogTap.drain() {
            hub.tap.append(AgentEventKind.log, [
                "category": .string(line.category), "message": .string(line.message)
            ])
        }
        for (kind, data) in hub.tap.pending {
            emit(kind, data)
        }
        hub.tap.pending.removeAll()
    }

    private func wireEventCallbacks() {
        let streamer = game.streamer
        guard !hub.tap.wired else { return }
        hub.tap.wired = true
        streamer.registerCellAttached(.agentEvents) { [weak state = hub.state] attachment in
            // A rebuild of the same cell after a state change is not a new load.
            guard attachment.isFirstIntegration else { return }
            state?.tap.append(AgentEventKind.cellLoaded, Self.cellData(attachment.scene))
        }
        streamer.onCellDetached.register(.agentEvents) { [weak state = hub.state] location in
            state?.tap.append(AgentEventKind.cellUnloaded, Self.locationData(location))
        }
        streamer.onInteraction.register(.agentEvents) { [weak state = hub.state] event in
            state?.tap.append(
                AgentEventKind.activation,
                Self.interactionData(event.target.interaction)
            )
        }
        streamer.activationGate.refusals.register(.agentEvents) { [weak state = hub.state] event in
            var data = Self.interactionData(event.target.interaction)
            if case let .locked(level, _) = event.refusal {
                data["reason"] = "locked"
                data["lockLevel"] = .init(Int(level))
            } else if event.refusal == .filteredByPerk {
                data["reason"] = "perk"
            } else if event.refusal == .mounted {
                data["reason"] = "mounted"
            }
            state?.tap.append(AgentEventKind.activationRefused, data)
        }
    }

    private static func cellData(_ scene: any CellScenePort) -> [String: AgentJSON] {
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
        guard menus != hub.tap.menus else { return }
        for name in hub.tap.menus where !menus.contains(name) {
            hub.tap.append(AgentEventKind.menuClosed, ["menu": .string(name)])
        }
        for name in menus where !hub.tap.menus.contains(name) {
            hub.tap.append(AgentEventKind.menuOpened, ["menu": .string(name)])
        }
        hub.tap.menus = menus
    }

    private func diffDeaths() {
        let streamer = game.streamer
        for entry in streamer.residentActorEntries() {
            let isDead = game.worldState.component(ActorDeathState.self, for: entry.key)?
                .isDead ?? false
            guard isDead, !hub.tap.dead.contains(entry.key) else { continue }
            hub.tap.dead.insert(entry.key)
            guard hub.tap.seeded else { continue }
            hub.tap.append(AgentEventKind.actorDeath, [
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
                let stage = state.stagesReached.last,
                hub.tap.questStages[editorID] != stage else { continue }
            hub.tap.questStages[editorID] = stage
            guard hub.tap.seeded else { continue }
            hub.tap.append(
                AgentEventKind.questStage,
                ["id": .string(editorID), "stage": .init(Int(stage))]
            )
        }
    }

    private func diffCombatAndScripts() {
        let melee = game.combat.meleeCombatSnapshot
        if melee.hitCount > hub.tap.hitCount, hub.tap.seeded, let hit = melee.trace.last {
            hub.tap.append(AgentEventKind.combatHit, [
                "target": .string(hit.target), "damage": .init(hit.appliedDamage)
            ])
        }
        hub.tap.hitCount = melee.hitCount
        let scripts = game.scripts.scriptsSnapshot
        if
            scripts.tickCount != hub.tap.scriptTick, scripts.lastTickFaulted > 0,
            hub.tap.seeded
        {
            hub.tap.append(AgentEventKind.scriptError, [
                "faulted": .init(scripts.lastTickFaulted), "tick": .init(scripts.tickCount),
                "fault": .init(scripts.lastFault)
            ])
        }
        hub.tap.scriptTick = scripts.tickCount
    }

    public func changesState(limit: Int) -> AgentJSON {
        let entries = game.worldState.journalEntries.suffix(max(0, limit))
        var fields: [String: AgentJSON] = [
            "changes": .array(entries.map(change))
        ]
        do {
            let streamer = game.streamer
            fields["transitionInFlight"] = streamer.transitionInFlight
                .map { .formID($0.rawValue) } ?? .null
            fields["interiorRebuilding"] = .bool(streamer.interiorRebuildInFlight)
            fields["interiorMutationSequence"] = .init(Int(streamer.interiorMutationSequence))
            fields["interiorSceneSequence"] = streamer.interiorScene
                .map { .init(Int($0.stateSequence)) } ?? .null
        }
        return .object(fields)
    }

    private func change(_ entry: WorldStateJournalEntry) -> AgentJSON {
        let formID = game.streamer.referenceEntry(key: entry.key)?.formID
        return [
            "sequence": .init(Int(entry.sequence)),
            "ref": formID.map { .formID($0.rawValue) } ?? .string(String(describing: entry.key)),
            "kind": .string(entry.kind.rawValue),
            "reset": .bool(entry.isReset)
        ]
    }

    public func setQuestStage(_ editorID: String, stage: Int) throws(AgentFailure) -> AgentJSON {
        guard let quests = game.journalMenu.questRuntime else {
            throw AgentFailure(.notReady, "no quest data is loaded")
        }
        guard let quest = quests.quests.quest(editorID: editorID) else {
            throw AgentFailure(.notFound, "no quest '\(editorID)'")
        }
        guard let index = UInt16(exactly: stage) else {
            throw AgentFailure(.invalidArgument, "stage must be 0 to 65535")
        }
        do {
            // Through the script bridge, as `SetStage` does, so the stage fragment runs.
            if let bridge = game.scripts.bridge, let key = quests.quests.key(for: quest.formID) {
                _ = try bridge.setQuestStage(index, for: key)
            } else {
                _ = try quests.setStage(index, on: quest.formID)
            }
            let state = try quests.state(of: quest.formID)
            return [
                "id": .string(editorID), "stage": .init(Int(index)),
                "running": .bool(state.isRunning), "completed": .bool(state.isCompleted)
            ]
        } catch {
            throw AgentFailure(.invalidArgument, "stage refused: \(error)")
        }
    }
}
