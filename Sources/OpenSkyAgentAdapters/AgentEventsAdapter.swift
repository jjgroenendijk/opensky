import Foundation
import OpenSkyActors
import OpenSkyActorsInterface
public import OpenSkyAgentControl
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyEffects
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyLoading
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyObjectAnimation
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyQuests
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkySaveInterface
import OpenSkyScripting
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
    var streamer: (any CellStreamerPort)? { get }
    var worldState: any WorldStateStorePort { get }
}

/// Part of `AgentWorldAdapter`, over its own narrow host.
public struct AgentEventsAdapter {
    public unowned let owner: AgentWorldAdapter
    public let game: any AgentEventsHost
}

extension AgentEventsAdapter {
    public static let slowPollSeconds = 0.25

    public func pollEvents(_ emit: (String, [String: AgentJSON]) -> Void) {
        wireEventCallbacks()
        diffMenus()
        let now = ProcessInfo.processInfo.systemUptime
        if now >= owner.tap.nextSlowPoll {
            owner.tap.nextSlowPoll = now + Self.slowPollSeconds
            diffDeaths()
            diffQuestStages()
            diffCombatAndScripts()
            owner.tap.seeded = true
        }
        for line in EngineLogTap.drain() {
            owner.tap.append(AgentEventKind.log, [
                "category": .string(line.category), "message": .string(line.message)
            ])
        }
        for (kind, data) in owner.tap.pending {
            emit(kind, data)
        }
        owner.tap.pending.removeAll()
    }

    private func wireEventCallbacks() {
        guard !owner.tap.wired, let streamer = game.streamer else { return }
        owner.tap.wired = true
        streamer.registerCellAttached(.agentEvents) { [weak owner] attachment in
            // A rebuild of the same cell after a state change is not a new load.
            guard attachment.isFirstIntegration else { return }
            owner?.tap.append(AgentEventKind.cellLoaded, Self.cellData(attachment.scene))
        }
        streamer.onCellDetached.register(.agentEvents) { [weak owner] location in
            owner?.tap.append(AgentEventKind.cellUnloaded, Self.locationData(location))
        }
        streamer.onInteraction.register(.agentEvents) { [weak owner] event in
            owner?.tap.append(
                AgentEventKind.activation,
                Self.interactionData(event.target.interaction)
            )
        }
        streamer.activationGate.refusals.register(.agentEvents) { [weak owner] event in
            var data = Self.interactionData(event.target.interaction)
            if case let .locked(level, _) = event.refusal {
                data["reason"] = "locked"
                data["lockLevel"] = .init(Int(level))
            } else if event.refusal == .filteredByPerk {
                data["reason"] = "perk"
            } else if event.refusal == .mounted {
                data["reason"] = "mounted"
            }
            owner?.tap.append(AgentEventKind.activationRefused, data)
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
        guard menus != owner.tap.menus else { return }
        for name in owner.tap.menus where !menus.contains(name) {
            owner.tap.append(AgentEventKind.menuClosed, ["menu": .string(name)])
        }
        for name in menus where !owner.tap.menus.contains(name) {
            owner.tap.append(AgentEventKind.menuOpened, ["menu": .string(name)])
        }
        owner.tap.menus = menus
    }

    private func diffDeaths() {
        guard let streamer = game.streamer else { return }
        for entry in streamer.residentActorEntries() {
            let isDead = game.worldState.component(ActorDeathState.self, for: entry.key)?
                .isDead ?? false
            guard isDead, !owner.tap.dead.contains(entry.key) else { continue }
            owner.tap.dead.insert(entry.key)
            guard owner.tap.seeded else { continue }
            owner.tap.append(AgentEventKind.actorDeath, [
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
                owner.tap.questStages[editorID] != stage else { continue }
            owner.tap.questStages[editorID] = stage
            guard owner.tap.seeded else { continue }
            owner.tap.append(
                AgentEventKind.questStage,
                ["id": .string(editorID), "stage": .init(Int(stage))]
            )
        }
    }

    private func diffCombatAndScripts() {
        let melee = game.combat.meleeCombatSnapshot
        if melee.hitCount > owner.tap.hitCount, owner.tap.seeded, let hit = melee.trace.last {
            owner.tap.append(AgentEventKind.combatHit, [
                "target": .string(hit.target), "damage": .init(hit.appliedDamage)
            ])
        }
        owner.tap.hitCount = melee.hitCount
        let scripts = game.scripts.scriptsSnapshot
        if
            scripts.tickCount != owner.tap.scriptTick, scripts.lastTickFaulted > 0,
            owner.tap.seeded
        {
            owner.tap.append(AgentEventKind.scriptError, [
                "faulted": .init(scripts.lastTickFaulted), "tick": .init(scripts.tickCount),
                "fault": .init(scripts.lastFault)
            ])
        }
        owner.tap.scriptTick = scripts.tickCount
    }

    public func changesState(limit: Int) -> AgentJSON {
        let entries = game.worldState.journalEntries.suffix(max(0, limit))
        var fields: [String: AgentJSON] = [
            "changes": .array(entries.map(change))
        ]
        if let streamer = game.streamer {
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
        let formID = game.streamer?.referenceEntry(key: entry.key)?.formID
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
