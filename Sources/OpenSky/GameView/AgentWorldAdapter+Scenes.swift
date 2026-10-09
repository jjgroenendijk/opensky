// The answers to `openskycli game state scenes` and `state scripts`, from the
// same snapshots the Scenes and Scripts sections read.

import Foundation
import OpenSkyAgentControl
import OpenSkyDialogue
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuestsInterface
import OpenSkyScripting
import OpenSkyScriptingInterface

extension AgentWorldAdapter {
    func scenesState() -> AgentJSON {
        let snapshot = game.scenes.sceneSnapshot
        let playing = snapshot.playing.map { row -> AgentJSON in
            [
                "id": .string(row.editorID),
                "phase": .init(row.phase),
                "phaseCount": .init(row.phaseCount),
                "phaseName": row.phaseName.map(AgentJSON.string) ?? .null,
                "running": .array(row.runningActions.map { .init(Int($0)) })
            ]
        }
        return [
            "playing": .array(playing),
            "trace": .array(snapshot.trace.map(AgentJSON.string)),
            "lines": .array(snapshot.lines.map(AgentJSON.string))
        ]
    }
}

extension AgentWorldAdapter {
    /// The answer to `openskycli game state scripts`: queue, waits, the newest events,
    /// the newest fault, and the natives that are missing most.
    func scriptsState(reference: String?) throws(AgentFailure) -> AgentJSON {
        let snapshot = game.scripts.scriptsSnapshot
        let instances = try reference.map { text throws(AgentFailure) in
            try instancesState(on: scriptOwner(text))
        } ?? .null
        return [
            "on": instances,
            "instances": .init(snapshot.instanceCount),
            "pendingEvents": .init(snapshot.pendingEventCount),
            "pendingWaits": .init(snapshot.pendingWaitCount),
            "recentEvents": .array(snapshot.recentEvents.map(AgentJSON.string)),
            "lastFault": snapshot.lastFault.map(AgentJSON.string) ?? .null,
            "unimplemented": .array(snapshot.topUnimplementedNatives.map {
                ["name": .string($0.name), "count": .init($0.count)]
            })
        ]
    }

    /// A quest editor ID, else a reference as `resolveReference` reads it.
    private func scriptOwner(_ text: String) throws(AgentFailure) -> ReferenceKey {
        if let quest = game.scripts.bridge?.questRuntime?.quests.key(editorID: text) {
            return quest
        }
        return try resolveReference(text).key
    }

    /// Live variables, so an object shows the reference it holds; a save keeps none.
    private func instancesState(on key: ReferenceKey) -> AgentJSON {
        guard let world = game.scripts.runtime else { return .array([]) }
        let keys = world.instancesByKey.keys.filter { $0.reference == key }.sorted()
        return .array(keys.compactMap { instanceKey -> AgentJSON? in
            guard
                let handle = world.instancesByKey[instanceKey],
                let instance = world.runtime.instance(for: handle)
            else { return nil }
            return [
                "script": .string(instanceKey.scriptName),
                "state": .string(instance.activeState),
                "variables": .array(instance.sortedVariableStates().map {
                    .string("\($0.name) = \(variableText($0.value, in: world))")
                })
            ]
        })
    }

    private func variableText(_ value: PapyrusValue, in world: PapyrusWorldRuntime) -> String {
        guard case let .object(handle) = value else { return "\(value)" }
        return world.referenceKey(for: handle).map { "object(\($0))" } ?? "\(value)"
    }
}
