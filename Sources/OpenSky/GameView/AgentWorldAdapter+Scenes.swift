// The answers to `openskycli game state scenes` and `state scripts`, from the
// same snapshots the Scenes and Scripts sections read.

import Foundation
import OpenSkyAgentControl
import OpenSkyDialogue
import OpenSkyDialogueInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuestsInterface
import OpenSkyScriptingInterface
import OpenSkySessionInterface

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
        let owner = try reference.map { text throws(AgentFailure) in try scriptOwner(text) }
        return [
            "on": owner.map(instancesState(on:)) ?? .null,
            "waits": owner.map(waitsState(on:)) ?? .null,
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

    /// The calls the reference's scripts wait in, such as `Utility.Wait` or an
    /// animation event, so a stalled script shows where it stopped.
    private func waitsState(on key: ReferenceKey) -> AgentJSON {
        guard let world = game.scripts.runtime else {
            return .array([])
        }
        return .array(world.waits(on: key).map { wait in
            [
                "script": .string(wait.script),
                "native": .string(wait.native),
                "request": .string(wait.request)
            ]
        })
    }

    private func instancesState(on key: ReferenceKey) -> AgentJSON {
        guard let world = game.scripts.runtime else { return .array([]) }
        return .array(world.instances(on: key).map { instance in
            [
                "script": .string(instance.script),
                "state": .string(instance.state),
                "variables": .array(instance.variables.map(AgentJSON.string))
            ]
        })
    }
}
