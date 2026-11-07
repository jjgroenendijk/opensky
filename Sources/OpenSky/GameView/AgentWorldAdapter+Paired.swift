// `openskycli game debug paired` plays an idle with a target, as `PlayIdleWithTarget`
// does, and `state paired` reads each pair (docs/engine/paired-animations.md).

import OpenSkyActorPresentation
import OpenSkyAgentControl
import OpenSkyBehavior
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPlayer
import OpenSkyWorld

extension AgentWorldAdapter {
    func playPaired(
        _ reference: String, target: String, idle editorID: String
    ) throws(AgentFailure) -> AgentJSON {
        let lead = try resolveReference(reference)
        let partner = try resolveReference(target)
        let idles = game.idleWorld.idles
        guard let idle = idles.store?.idles.record(editorID: editorID) else {
            throw AgentFailure(.notFound, "no idle '\(editorID)'")
        }
        let report = idles.fireIdle(
            idle.id, on: lead.key, target: partner.key, ignoringConditions: true
        )
        return [
            "idle": .string(editorID), "chosen": AgentJSON(report?.chosen),
            "failure": AgentJSON(report?.failure), "pairs": pairsJSON()
        ]
    }

    func pairedState() -> AgentJSON {
        ["pairs": pairsJSON()]
    }

    private func pairsJSON() -> AgentJSON {
        .array(game.idleWorld.idles.pairs.map { play in
            [
                "idle": .string(play.idle), "event": .string(play.event),
                "killMove": .bool(play.isKillMove),
                "partnerTookEvent": .bool(play.partnerTookEvent),
                "partnerAtMark": .bool(play.isAtMark),
                "lead": actorJSON(play.lead), "partner": actorJSON(play.partner)
            ]
        })
    }

    /// The paired clips the actor's graph sampled, as the track prefix, `|`, and the clip.
    private func actorJSON(_ key: ReferenceKey) -> AgentJSON {
        let graph = key == .player
            ? game.gameSession?.locomotion.graph
            : game.actorGraphs.instance(of: key)
        return [
            "ref": .string("\(key)"),
            "clips": .array((graph?.pairedClipNames ?? []).map { .string($0) }),
            "getToMarkTime": graph?.synchronizedMark.map { .number(Double($0.getToMarkTime)) }
                ?? .null
        ]
    }
}
