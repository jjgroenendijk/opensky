// `debug grab` and `state grab`: the player's grab (docs/engine/grab.md).

import OpenSkyAgentControl
import OpenSkyPhysics
import OpenSkySessionInterface

extension AgentChangesAdapter {
    func grab(_ text: String?) throws(AgentFailure) -> AgentJSON {
        let grab = game.playerGrab
        guard let text else {
            grab.letGo()
            return try grabState()
        }
        let key = try reference(text)
        guard grab.grabReadout.isEnabled else {
            throw AgentFailure(.invalidArgument, "the grab setting is off")
        }
        guard grab.grab(key) else {
            throw AgentFailure(
                .invalidArgument, "\(text) is not a loose object or dead body that can be held"
            )
        }
        return try grabState()
    }

    func grabState() throws(AgentFailure) -> AgentJSON {
        let readout = game.playerGrab.grabReadout
        return [
            "enabled": .bool(readout.isEnabled),
            "phase": .string(readout.phase),
            "held": readout.held.map(AgentJSON.formID) ?? .null,
            "body": readout.body.map { .init($0) } ?? .null,
            "distance": readout.distance.map { .init($0) } ?? .null,
            "force": readout.strength.map { .init($0.force) } ?? .null,
            "elasticity": readout.strength.map { .init($0.elasticity) } ?? .null,
            "lastLetGo": readout.lastLetGo.map(AgentJSON.string) ?? .null
        ]
    }
}
