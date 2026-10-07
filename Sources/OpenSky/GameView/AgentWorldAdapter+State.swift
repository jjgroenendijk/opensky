// Read-only answers for `openskycli game state ...`. References are "player",
// "target", or a hex FormID of a resident reference.

import Foundation
import OpenSkyActors
import OpenSkyAgentControl
import OpenSkyCombat
import OpenSkyDiagnostics
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuests
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

struct AgentReference {
    let key: ReferenceKey
    let formID: FormID
}

extension AgentWorldAdapter {
    func query(_ query: AgentStateQuery) throws(AgentFailure) -> AgentJSON {
        switch query {
        case .player: try playerState()
        case .target: targetState()
        case let .actors(radius): try actorsState(radius: radius)
        case .menu: menuState
        case let .quest(editorID): try questState(editorID)
        case let .actorValue(reference, name): try actorValueState(reference, name: name)
        case let .global(editorID): try globalState(editorID)
        case .time: timeState()
        case .frame: frameState()
        }
    }

    func resolveReference(_ text: String) throws(AgentFailure) -> AgentReference {
        switch text.lowercased() {
        case "player":
            return AgentReference(key: .player, formID: FormID(0x14))
        case "target":
            guard let target = game.streamer?.interactionTarget else {
                throw AgentFailure(.notFound, "nothing is under the crosshair")
            }
            return try resolveFormID(target.interaction.reference)
        default:
            let digits = text.hasPrefix("0x") || text
                .hasPrefix("0X") ? String(text.dropFirst(2)) : text
            guard let raw = UInt32(digits, radix: 16) else {
                throw AgentFailure(.invalidArgument, "ref must be player, target, or a hex FormID")
            }
            return try resolveFormID(FormID(raw))
        }
    }

    private func resolveFormID(_ formID: FormID) throws(AgentFailure) -> AgentReference {
        guard let entry = game.streamer?.referenceEntry(formID: formID) else {
            throw AgentFailure(
                .notFound,
                "no loaded reference \(AgentJSON.formID(formID.rawValue))"
            )
        }
        return AgentReference(key: entry.key, formID: formID)
    }

    func actorValueHolder(for reference: AgentReference) throws(AgentFailure) -> ActorValueHolder {
        guard let holder = game.actorWorld.actorValueHolder(for: reference.key) else {
            throw AgentFailure(
                .notFound,
                "\(AgentJSON.formID(reference.formID.rawValue)) is not a loaded actor"
            )
        }
        return holder
    }

    func actorValueIndex(_ name: String) throws(AgentFailure) -> Int32 {
        guard let index = ActorValueIdentity.index(named: name) else {
            throw AgentFailure(.invalidArgument, "unknown actor value '\(name)'")
        }
        return index
    }

    private func playerState() throws(AgentFailure) -> AgentJSON {
        guard let renderer = game.renderer else { throw notReady() }
        let camera = renderer.freeFlyCamera
        var result: [String: AgentJSON] = [
            "position": .init(camera.position),
            "yaw": .init(remainder(camera.yaw * 180 / .pi, 360)),
            "pitch": .init(camera.pitch * 180 / .pi),
            "movementMode": .string(String(describing: renderer.movementMode)),
            "cell": cellState(at: camera.position)
        ]
        if let values = game.actorValues.runtime {
            let current = values.current(of: .player)
            let maximum = values.maximums(of: .player)
            result["health"] = ["current": .init(current.health), "max": .init(maximum.health)]
            result["magicka"] = ["current": .init(current.magicka), "max": .init(maximum.magicka)]
            result["stamina"] = ["current": .init(current.stamina), "max": .init(maximum.stamina)]
        }
        return .object(result)
    }

    private func cellState(at position: SIMD3<Float>) -> AgentJSON {
        guard let streamer = game.streamer else { return .null }
        if let interior = streamer.interiorScene {
            return ["interior": true, "name": .string(interior.summary.cellName)]
        }
        let grid = CellCoordinate(containing: position)
        return [
            "interior": false, "x": .init(Int(grid.x)), "y": .init(Int(grid.y)),
            "name": .init(streamer.composition.cells[grid]?.summary.cellName)
        ]
    }

    private func targetState() -> AgentJSON {
        guard let target = game.streamer?.interactionTarget else { return .null }
        let interaction = target.interaction
        return [
            "ref": .formID(interaction.reference.rawValue),
            "base": .formID(interaction.base.rawValue),
            "name": .string(interaction.name),
            "action": .string(interaction.actionLabel),
            "distance": .init(target.distance),
            "position": .init(interaction.position)
        ]
    }

    private func actorsState(radius: Float) throws(AgentFailure) -> AgentJSON {
        guard let renderer = game.renderer else { throw notReady() }
        let origin = renderer.freeFlyCamera.position
        let rows: [(Float, AgentJSON)] = game.actorWorld.combatActors().compactMap { actor in
            let distance = simd_distance(actor.feet, origin)
            guard distance <= radius else { return nil }
            let formID = game.streamer?.referenceEntry(key: actor.key)?.formID
            return (distance, [
                "ref": formID.map { .formID($0.rawValue) } ?? .null,
                "name": .string(game.dialogueWorld.speakerLabel(for: actor.key)),
                "position": .init(actor.feet),
                "distance": .init(distance),
                "dead": .bool(actor.isDead)
            ])
        }
        return ["actors": .array(rows.sorted { $0.0 < $1.0 }.map(\.1))]
    }

    private func questState(_ editorID: String) throws(AgentFailure) -> AgentJSON {
        guard let quests = game.journalMenu.questRuntime else {
            throw AgentFailure(.notReady, "no quest data is loaded")
        }
        guard let state = try? quests.state(editorID: editorID) else {
            throw AgentFailure(.notFound, "no quest '\(editorID)'")
        }
        return [
            "id": .string(editorID),
            "stage": state.stagesReached.last.map { .init(Int($0)) } ?? .null,
            "stagesDone": .array(state.stagesReached.map { .init(Int($0)) }),
            "running": .bool(state.isRunning),
            "completed": .bool(state.isCompleted)
        ]
    }

    private func actorValueState(_ text: String, name: String) throws(AgentFailure) -> AgentJSON {
        guard let values = game.actorValues.runtime else {
            throw AgentFailure(.notReady, "actor values are not loaded")
        }
        let reference = try resolveReference(text)
        let holder = try actorValueHolder(for: reference)
        let index = try actorValueIndex(name)
        guard let value = values.value(at: index, on: holder) else {
            throw AgentFailure(.notFound, "\(name) has no value on this actor")
        }
        return [
            "ref": .formID(reference.formID.rawValue),
            "name": .string(name),
            "value": .init(value)
        ]
    }

    private func globalState(_ editorID: String) throws(AgentFailure) -> AgentJSON {
        guard let global = game.runtimeState.runtimeStateGlobal(editorID: editorID) else {
            throw AgentFailure(.notFound, "no global '\(editorID)'")
        }
        return [
            "id": .string(global.editorID), "value": .init(global.currentValue),
            "default": .init(global.defaultValue), "overridden": .bool(global.isOverridden)
        ]
    }

    private func timeState() -> AgentJSON {
        let clock = game.runtimeState.runtimeStateClock
        return [
            "hour": .init(clock.hourOfDay), "day": .init(clock.day),
            "month": .string(clock.monthName),
            "year": .init(clock.year), "daysPassed": .init(clock.daysPassed),
            "timescale": .init(clock.timescale), "simulation": agentTimeline.json
        ]
    }

    private func frameState() -> AgentJSON {
        let stats = game.renderControls.frameStatsSnapshot
        return [
            "timeline": agentTimeline.json,
            "fps": .number(stats.fps), "frameMS": .number(stats.frameMS),
            "maxFrameMS": .number(stats.maxFrameMS),
            "gpuMS": stats.gpuMS.map(AgentJSON.number) ?? .null,
            "memoryMB": MemoryFootprint.physFootprintMB().map(AgentJSON.number) ?? .null,
            "interpolation": interpolationState()
        ]
    }

    private func interpolationState() -> AgentJSON {
        guard let status = game.renderControls.renderPerformanceSnapshot?.frameInterpolation
        else { return .null }
        return [
            "enabled": .bool(status.enabled), "running": .bool(status.isRunning),
            "shownFPS": .number(status.shownFPS),
            "builtFrames": .init(status.interpolatedFrames),
            "presentLatencyMS": status.presentLatencyMS.map(AgentJSON.number) ?? .null
        ]
    }
}
