// Read-only answers for `openskycli game state ...`. References are "player",
// "target", or a hex FormID of a resident reference.

import Foundation
import OpenSkyActorPresentation
import OpenSkyActorsInterface
public import OpenSkyAgentControl
import OpenSkyAudio
import OpenSkyBehavior
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyCrimeInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWeather
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

public struct AgentReference {
    public let key: ReferenceKey
    public let formID: FormID
}

extension AgentWorldAdapter {
    public func query(_ query: AgentStateQuery) throws(AgentFailure) -> AgentJSON {
        switch query {
        case .player: try playerReadout.playerState()
        case .target: actorReadout.targetState()
        case let .actors(radius): try actorReadout.actorsState(radius: radius)
        case .menu: menuReadout.menuState
        case let .quest(editorID): try menuReadout.questState(editorID)
        case .scenes: objects.scenesState()
        case .scripts, .packages, .furniture, .objects, .effects, .nodes, .changes, .flight,
             .mount, .paired, .favor, .impulses:
            try inspection(query)
        case let .actorValue(reference, name): try actorReadout.actorValueState(
                reference,
                name: name
            )
        case let .global(editorID): try frameReadout.globalState(editorID)
        case .time: frameReadout.timeState()
        case .frame: frameReadout.frameState()
        case .view, .newGame: try sessionState(query)
        }
    }

    private func sessionState(_ query: AgentStateQuery) throws(AgentFailure) -> AgentJSON {
        if case .newGame = query {
            return game.menuWorld.lastNewGame?.json ?? ["start": .null]
        }
        return try view.viewState()
    }

    /// The reads that look inside the scripts, the packages, and the seats.
    private func inspection(_ query: AgentStateQuery) throws(AgentFailure) -> AgentJSON {
        switch query {
        case let .scripts(reference): try objects.scriptsState(reference: reference)
        case let .packages(reference): try behaviour.packagesState(reference: reference)
        case let .furniture(reference): try behaviour.furnitureState(reference: reference)
        case let .objects(reference): try objects.objectsState(reference: reference)
        case let .effects(reference): try objects.effectsState(reference: reference)
        case let .nodes(reference): try objects.nodesState(reference: reference)
        case let .changes(limit): events.changesState(limit: limit)
        case let .flight(reference): try motion.flightState(reference: reference)
        default: try riderInspection(query)
        }
    }

    /// The reads of what a rider, a pair, or the player's favours hold.
    private func riderInspection(_ query: AgentStateQuery) throws(AgentFailure) -> AgentJSON {
        switch query {
        case .mount: motion.mountState()
        case .paired: behaviour.pairedState()
        case .favor: objects.favorState()
        case .impulses: motion.impulsesState()
        default: throw AgentFailure(.invalidArgument, "not an inspection query")
        }
    }
}

extension AgentHub {
    public func resolveReference(_ text: String) throws(AgentFailure) -> AgentReference {
        switch text.lowercased() {
        case "player":
            return AgentReference(key: .player, formID: .playerReference)
        case "target":
            guard let target = game.streamer.interactionTarget else {
                throw AgentFailure(.notFound, "nothing is under the crosshair")
            }
            return try resolveFormID(target.interaction.reference)
        default:
            guard let formID = FormID(hexText: text) else {
                throw AgentFailure(.invalidArgument, "ref must be player, target, or a hex FormID")
            }
            return try resolveFormID(formID)
        }
    }

    private func resolveFormID(_ formID: FormID) throws(AgentFailure) -> AgentReference {
        guard let entry = game.streamer.referenceEntry(formID: formID) else {
            throw AgentFailure(
                .notFound,
                "no loaded reference \(AgentJSON.formID(formID.rawValue))"
            )
        }
        return AgentReference(key: entry.key, formID: formID)
    }

    public func actorValueHolder(for reference: AgentReference) throws(AgentFailure)
        -> ActorValueHolder
    {
        guard let holder = game.actorWorld.actorValueHolder(for: reference.key) else {
            throw AgentFailure(
                .notFound,
                "\(AgentJSON.formID(reference.formID.rawValue)) is not a loaded actor"
            )
        }
        return holder
    }

    public func actorValueIndex(_ name: String) throws(AgentFailure) -> Int32 {
        guard let index = ActorValueIdentity.index(named: name) else {
            throw AgentFailure(.invalidArgument, "unknown actor value '\(name)'")
        }
        return index
    }
}
