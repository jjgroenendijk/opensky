import Foundation
import OpenSkyActors
import OpenSkyActorsInterface
public import OpenSkyAgentControl
import OpenSkyEffects
import OpenSkyFormatsESM
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

/// What `AgentItemsAdapter` reads from the session.
@MainActor
public protocol AgentItemsHost: AnyObject {
    var actorValues: any ActorValuePort { get }
    var inventory: any InventoryPort { get }
    var inventoryWorld: any InventoryWorldPort { get }
    var scripts: any ScriptPort { get }
    var worldState: any WorldStateStorePort { get }
}

/// Part of `AgentWorldAdapter`, over its own narrow host.
public struct AgentItemsAdapter {
    public unowned let owner: AgentWorldAdapter
    public let game: any AgentItemsHost
}

extension AgentItemsAdapter {
    public func changeActor(_ command: AgentDebugCommand) throws(AgentFailure) -> AgentJSON {
        switch command {
        case let .setActorValue(reference, name, value):
            try writeActorValue(reference, name: name) { values, index, holder, _ in
                values.setBase(at: index, to: value, on: holder)
            }
        case let .modActorValue(reference, name, delta):
            try writeActorValue(reference, name: name) { values, index, holder, before in
                values.setValue(at: index, to: before + delta, on: holder)
            }
        case let .addItem(reference, item, count, equip):
            try changeItem(reference, item: item, by: count, equip: equip)
        case let .removeItem(reference, item, count):
            try changeItem(reference, item: item, by: -count)
        default:
            throw AgentFailure(.invalidArgument, "not an actor change")
        }
    }

    private func writeActorValue(
        _ text: String,
        name: String,
        _ write: (any ActorValueRuntimePort, Int32, ActorValueHolder, Float) -> Bool
    ) throws(AgentFailure) -> AgentJSON {
        guard let values = game.actorValues.runtime else {
            throw AgentFailure(.notReady, "actor values are not loaded")
        }
        let reference = try owner.resolveReference(text)
        let holder = try owner.actorValueHolder(for: reference)
        let index = try owner.actorValueIndex(name)
        let before = values.value(at: index, on: holder) ?? 0
        _ = write(values, index, holder, before)
        return [
            "ref": .formID(reference.formID.rawValue), "name": .string(name),
            "before": .init(before), "value": .init(values.value(at: index, on: holder) ?? 0),
            "base": .init(values.baseValue(at: index, on: holder) ?? 0)
        ]
    }

    /// Only the player carries an inventory an agent can change.
    private func changeItem(
        _ text: String,
        item editorID: String,
        by count: Int32,
        equip: Bool = false
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
        var result: [String: AgentJSON] = [
            "item": .string(editorID), "name": .string(game.inventory.name(of: definition.formID)),
            "count": .init(Int(runtime.inventory.count(of: definition.formID, in: runtime.player)))
        ]
        if equip {
            let outcome = game.inventoryWorld.run(
                game.inventory.equipItem(definition.formID, on: .player)
            )
            guard case .equipped = outcome else {
                throw AgentFailure(.invalidArgument, "equip refused: \(outcome.text)")
            }
            result["equipped"] = true
        }
        return .object(result)
    }

    public func kill(_ text: String) throws(AgentFailure) -> AgentJSON {
        let reference = try owner.resolveReference(text)
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
    public func resurrect(_ text: String) throws(AgentFailure) -> AgentJSON {
        guard let values = game.actorValues.runtime else {
            throw AgentFailure(.notReady, "actor values are not loaded")
        }
        let reference = try owner.resolveReference(text)
        let holder = try owner.actorValueHolder(for: reference)
        game.worldState.reset(ActorDeathState.componentKind, for: reference.key)
        values.restoreAll(on: holder)
        return ["ref": .formID(reference.formID.rawValue), "dead": false]
    }
}
