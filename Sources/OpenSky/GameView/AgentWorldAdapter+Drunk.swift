// `openskycli game debug drunk`: raise the drunk idle's event on an actor's graph
// (docs/engine/actor-state-graph.md).

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
}
