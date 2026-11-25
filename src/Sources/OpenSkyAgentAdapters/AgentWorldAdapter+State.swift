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
        try StateQueries(owner: self).query(query)
    }

    private func sessionState(_ query: AgentStateQuery) throws(AgentFailure) -> AgentJSON {
        switch query {
        case .newGame: game.menuWorld.lastNewGame?.json ?? ["start": .null]
        case .music: changes.musicState()
        case .sounds: render.soundsState()
        case .story: objects.storyState()
        case .social: socialState()
        case .stats: frameReadout.statsState()
        case .grab: try changes.grabState()
        case let .condition(probe):
            try conditionState(probe)
        default: try view.viewState()
        }
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
        try StateQueries(owner: self).riderInspection(query)
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

extension AgentWorldAdapter {
    /// Answers the agent's state queries.
    struct StateQueries {
        let owner: AgentWorldAdapter

        func query(_ query: AgentStateQuery) throws(AgentFailure) -> AgentJSON {
            switch query {
            case .player: try owner.playerReadout.playerState()
            case .target: owner.actorReadout.targetState()
            case let .actors(radius, detailed):
                try owner.actorReadout.actorsState(radius: radius, detailed: detailed)
            case .menu: AgentMenuState(owner: owner.menuReadout).menuState
            case let .quest(editorID): try owner.menuReadout.questState(editorID)
            case .scenes: owner.objects.scenesState()
            case .scripts, .packages, .furniture, .objects, .effects, .nodes, .changes, .flight,
                 .mount, .paired, .favor, .alarm, .impulses, .cloth, .assist, .projectiles,
                 .destruction:
                try owner.inspection(query)
            case let .actorValue(reference, name): try owner.actorReadout.actorValueState(
                    reference,
                    name: name
                )
            case let .global(editorID): try owner.frameReadout.globalState(editorID)
            case .time: owner.frameReadout.timeState()
            case .frame: owner.frameReadout.frameState()
            case .view, .newGame, .music, .sounds, .condition, .grab, .story, .social, .stats:
                try owner.sessionState(query)
            }
        }

        func riderInspection(_ query: AgentStateQuery) throws(AgentFailure) -> AgentJSON {
            let hub = owner.hub
            return switch query {
            case .mount: owner.motion.mountState()
            case .paired: owner.behaviour.pairedState()
            case .favor: owner.objects.favorState()
            case .alarm:
                AgentAlarmReadout(hub: owner.objects.hub, game: owner.objects.game).alarmState()
            case .impulses: owner.motion.impulsesState()
            case .cloth: owner.objects.clothState()
            case .assist: AgentAssistReadout(hub: hub).assistState()
            case .projectiles: AgentAssistReadout(hub: hub).projectilesState()
            case .destruction: AgentDestructionReadout(game: hub.hosts).destructionState()
            default: throw AgentFailure(.invalidArgument, "not an inspection query")
            }
        }
    }
}
