// `openskycli game debug drunk`: raise the drunk idle's event on an actor's graph
// (docs/engine/actor-state-graph.md). `debug form`: put the player in a beast form or end
// it (docs/engine/beast-forms.md).

import OpenSkyActorPresentation
import OpenSkyAgentControl
import OpenSkyFormatsESM
import OpenSkyPlayer
import OpenSkyWorld

extension AgentWorldAdapter {
    func setDrunk(_ reference: String, drunk: Bool) throws(AgentFailure) -> AgentJSON {
        let actor = try resolveReference(reference)
        let event = drunk ? ActorGraphNames.drunkStart : ActorGraphNames.drunkStop
        let taken: Bool
        if actor.key == .player {
            guard let locomotion = game.gameSession?.locomotion else { throw notReady() }
            taken = locomotion.raiseGraphEvent(named: event)
        } else {
            guard game.actorGraphs.instance(of: actor.key) != nil else {
                throw AgentFailure(.invalidArgument, "\(reference) runs no behaviour graph")
            }
            taken = game.actorGraphs.raise(event, on: actor.key)
        }
        return [
            "ref": .formID(actor.formID.rawValue), "event": .string(event), "taken": .bool(taken)
        ]
    }

    func forceBeastForm(_ name: String) throws(AgentFailure) -> AgentJSON {
        let forms: [String: PlayerBeastForm] = [
            "none": .none, "werewolf": .werewolf, "vampirelord": .vampireLord
        ]
        guard let form = forms[name] else {
            throw AgentFailure(.invalidArgument, "form must be werewolf, vampirelord, or none")
        }
        guard game.beastForms.force(form) else {
            throw AgentFailure(.notFound, "the \(name) race is not in the load order")
        }
        return ["form": .string(game.playerBeastForm.rawValue)]
    }
}
