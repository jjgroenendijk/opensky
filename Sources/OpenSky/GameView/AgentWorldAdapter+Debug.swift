// `openskycli game debug ...`: console-style changes to the running game. Each
// answers with the value as stored afterwards, so a script can check it.

import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyAgentControl
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMenus
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyQuests
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldState

extension AgentWorldAdapter {
    /// Overlays, then the render-debug layers, such as `distantlod`.
    static let overlayNames = ["navmesh", "path", "detection", "hud", "ui"]
        + RenderLayer.ordered.map { $0.identifierFragment.lowercased() }

    func perform(_ command: AgentDebugCommand) throws(AgentFailure) -> AgentHandling {
        switch command {
        case let .teleport(target):
            return try .waiting(AgentTeleportJob(adapter: self, target: target).wait)
        case let .setTime(hour):
            game.runtimeState.setGameClockHour(hour)
            return done(["hour": .init(game.runtimeState.runtimeStateClock.hourOfDay)])
        case let .weather(editorID):
            return try done(forceWeather(editorID))
        case .setActorValue, .modActorValue, .addItem, .removeItem:
            return try done(changeActor(command))
        case let .setQuestStage(quest, stage):
            return try done(setQuestStage(quest, stage: stage))
        case .kill, .resurrect, .flight:
            return try done(actorDebug(command))
        case .overlay, .channel, .shadows:
            return try done(renderDebug(command))
        case let .raceMenu(limited):
            return try done(openRaceMenu(limited: limited))
        case let .skillsMenu(sky, levels):
            return try done(openSkillsMenu(sky: sky, levels: levels))
        case let .benchmark(request):
            return try benchmark(request)
        case .sit, .stand, .passTime:
            return try done(performFurniture(command))
        }
    }

    private func actorDebug(_ command: AgentDebugCommand) throws(AgentFailure) -> AgentJSON {
        switch command {
        case let .kill(reference): try kill(reference)
        case let .resurrect(reference): try resurrect(reference)
        case let .flight(reference, order): try orderFlight(reference, order: order)
        default: throw AgentFailure(.invalidArgument, "not an actor debug command")
        }
    }

    private func renderDebug(_ command: AgentDebugCommand) throws(AgentFailure) -> AgentJSON {
        switch command {
        case let .overlay(name, enabled): try setOverlay(name, enabled: enabled)
        case let .channel(name): try setChannel(name)
        case let .shadows(name): try setShadowQuality(name)
        default: throw AgentFailure(.invalidArgument, "not a render debug command")
        }
    }

    private func changeActor(_ command: AgentDebugCommand) throws(AgentFailure) -> AgentJSON {
        switch command {
        case let .setActorValue(reference, name, value):
            try writeActorValue(reference, name: name) { _ in value }
        case let .modActorValue(reference, name, delta):
            try writeActorValue(reference, name: name) { $0 + delta }
        case let .addItem(reference, item, count):
            try changeItem(reference, item: item, by: count)
        case let .removeItem(reference, item, count):
            try changeItem(reference, item: item, by: -count)
        default:
            throw AgentFailure(.invalidArgument, "not an actor change")
        }
    }

    private func openRaceMenu(limited: Bool) throws(AgentFailure) -> AgentJSON {
        guard game.raceMenu.isOpen || game.raceMenu.open(limited: limited) else {
            throw AgentFailure(.notReady, "the race menu needs a loaded world")
        }
        return ["open": true, "limited": .bool(game.raceMenu.snapshot.isLimited)]
    }

    private func openSkillsMenu(sky: Bool?, levels: Int) throws(AgentFailure) -> AgentJSON {
        let menu = game.skillsMenu
        if let sky {
            menu.setSkyEnabled(sky)
        }
        if levels > 0 {
            guard menu.model == nil, let leveling = game.progression.leveling else {
                throw AgentFailure(.notReady, "levels are earned before the menu opens")
            }
            for _ in 0 ..< levels {
                let missing = leveling.experienceForNextLevel - leveling.state.experience
                game.progression.awardCharacterExperience(max(1, missing))
                game.progression.applyEarnedLevels()
            }
        }
        guard menu.model != nil || menu.open() else {
            throw AgentFailure(.notReady, "the skills menu needs a loaded world")
        }
        return skillsMenuState(menu.snapshot)
    }

    private func done(_ value: AgentJSON) -> AgentHandling {
        .done(.success(value))
    }

    private func forceWeather(_ editorID: String?) throws(AgentFailure) -> AgentJSON {
        guard game.gameSession?.weather != nil else {
            throw AgentFailure(.notReady, "no weather data is loaded")
        }
        guard let editorID else {
            game.renderControls.forceWeather(named: nil)
            return ["forced": .null]
        }
        let names = game.renderControls.selectableWeatherNames
        guard let match = names.first(where: { $0.lowercased() == editorID.lowercased() }) else {
            throw AgentFailure(.notFound, "no selectable weather '\(editorID)'")
        }
        game.renderControls.forceWeather(named: match)
        return ["forced": .string(match)]
    }

    private func writeActorValue(
        _ text: String,
        name: String,
        _ update: (Float) -> Float
    ) throws(AgentFailure) -> AgentJSON {
        guard let values = game.actorValues.runtime else {
            throw AgentFailure(.notReady, "actor values are not loaded")
        }
        let reference = try resolveReference(text)
        let holder = try actorValueHolder(for: reference)
        let index = try actorValueIndex(name)
        let before = values.value(at: index, on: holder) ?? 0
        values.setValue(at: index, to: update(before), on: holder)
        return [
            "ref": .formID(reference.formID.rawValue), "name": .string(name),
            "before": .init(before), "value": .init(values.value(at: index, on: holder) ?? 0)
        ]
    }

    /// Only the player carries an inventory an agent can change.
    private func changeItem(
        _ text: String,
        item editorID: String,
        by count: Int32
    ) throws(AgentFailure) -> AgentJSON {
        guard text.lowercased() == "player" else {
            throw AgentFailure(.unsupported, "items can only be changed on the player")
        }
        guard let runtime = game.inventory.runtime else {
            throw AgentFailure(.notReady, "inventory data is not loaded")
        }
        guard let definition = runtime.inventory.baselines.items.definition(editorID: editorID)
        else {
            throw AgentFailure(.notFound, "no item '\(editorID)'")
        }
        do {
            if count > 0 {
                try runtime.inventory.add(definition.formID, count: count, to: runtime.player)
            } else {
                try runtime.inventory.remove(definition.formID, count: -count, from: runtime.player)
            }
        } catch {
            throw AgentFailure(.invalidArgument, "item change refused: \(error)")
        }
        return [
            "item": .string(editorID), "name": .string(game.inventory.name(of: definition.formID)),
            "count": .init(Int(runtime.inventory.count(of: definition.formID, in: runtime.player)))
        ]
    }

    private func setQuestStage(_ editorID: String, stage: Int) throws(AgentFailure) -> AgentJSON {
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

    private func kill(_ text: String) throws(AgentFailure) -> AgentJSON {
        let reference = try resolveReference(text)
        guard reference.key != .player else {
            throw AgentFailure(.unsupported, "the player cannot be killed from here")
        }
        guard let bridge = game.scripts.bridge else {
            throw AgentFailure(.notReady, "the script bridge is not loaded")
        }
        guard bridge.killActor(reference.key, killer: nil) else {
            throw AgentFailure(.failed, "the actor did not die")
        }
        return ["ref": .formID(reference.formID.rawValue), "dead": true]
    }

    /// Clears the death record and refills the values. A ragdoll keeps its
    /// pose until the cell reloads.
    private func resurrect(_ text: String) throws(AgentFailure) -> AgentJSON {
        guard let values = game.actorValues.runtime else {
            throw AgentFailure(.notReady, "actor values are not loaded")
        }
        let reference = try resolveReference(text)
        let holder = try actorValueHolder(for: reference)
        game.worldState.reset(ActorDeathState.componentKind, for: reference.key)
        values.restoreAll(on: holder)
        return ["ref": .formID(reference.formID.rawValue), "dead": false]
    }

    private func setOverlay(_ name: String, enabled: Bool) throws(AgentFailure) -> AgentJSON {
        guard let renderer = game.renderer else { throw notReady() }
        switch name.lowercased() {
        case "navmesh": renderer.navmeshOverlayEnabled = enabled
        case "path": renderer.pathOverlayEnabled = enabled
        case "detection": renderer.detectionOverlayEnabled = enabled
        case "hud": renderer.swfEnabled = enabled
        case "ui": renderer.uiEnabled = enabled
        default:
            guard let layer = Self.layer(named: name.lowercased()) else {
                let known = Self.overlayNames.joined(separator: ", ")
                throw AgentFailure(.invalidArgument, "unknown overlay '\(name)'; known: \(known)")
            }
            let layers = renderer.renderDebug.layers
            renderer.renderDebug.layers = enabled ? layers.union(layer) : layers.subtracting(layer)
        }
        return ["overlay": .string(name.lowercased()), "on": .bool(enabled)]
    }

    private func setChannel(_ name: String) throws(AgentFailure) -> AgentJSON {
        guard let renderer = game.renderer else { throw notReady() }
        let modes = RenderDebugMode.allCases
        guard let mode = modes.first(where: { "\($0)".lowercased() == name.lowercased() }) else {
            let known = modes.map { "\($0)".lowercased() }.joined(separator: ", ")
            throw AgentFailure(.invalidArgument, "unknown channel '\(name)'; known: \(known)")
        }
        renderer.renderDebug.mode = mode
        return ["channel": .string("\(mode)".lowercased())]
    }

    private func setShadowQuality(_ name: String) throws(AgentFailure) -> AgentJSON {
        guard let renderer = game.renderer else { throw notReady() }
        guard let quality = ShadowQuality(rawValue: name.lowercased()) else {
            let known = ShadowQuality.allCases.map(\.rawValue).joined(separator: ", ")
            throw AgentFailure(
                .invalidArgument,
                "unknown shadow quality '\(name)'; known: \(known)"
            )
        }
        renderer.shadowQuality = quality
        return ["shadows": .string(quality.rawValue)]
    }

    private static func layer(named name: String) -> RenderLayer? {
        RenderLayer.ordered.first { $0.identifierFragment.lowercased() == name }
    }
}
