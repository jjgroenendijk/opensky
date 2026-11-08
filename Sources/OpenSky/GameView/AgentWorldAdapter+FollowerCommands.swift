// `state.favor`, `debug.favor`, and `debug.teammate`: follower command mode from the terminal
// (docs/engine/follower-commands.md).

import OpenSkyAgentControl
import OpenSkyAIPackages
import OpenSkyFactions
import OpenSkyFactionsInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWorldInterface

extension AgentWorldAdapter {
    func favorState() -> AgentJSON {
        let commands = game.followerCommands
        var json: [String: AgentJSON] = [
            "phase": .string(Self.phaseName(commands.phase)),
            "follower": commands.phase.follower.flatMap(formID) ?? .null,
            "lastDecision": commands.lastDecision.map(decisionJSON) ?? .null,
            "lastOutcome": commands.lastOutcome.map { .string($0.rawValue) } ?? .null,
            "pickDistance": .init(commands.settings.pickDistance)
        ]
        switch commands.phase {
        case let .walking(_, task):
            json["task"] = taskJSON(task)
        case let .waiting(_, left):
            json["waitLeft"] = .init(left)
        case .idle, .choosing:
            break
        }
        return .object(json)
    }

    private func commandFollower(
        _ reference: String, target: String?, exit: Bool
    ) throws(AgentFailure) -> AgentJSON {
        let follower = try resolveReference(reference).key
        let commands = game.followerCommands
        if exit {
            guard commands.phase.follower == follower, commands.cancel() else {
                throw AgentFailure(.invalidArgument, "\(reference) is not in command mode")
            }
            return favorState()
        }
        if commands.phase.follower != follower || !commands.isChoosing {
            game.followerCommandWorld.enterCommandMode(follower)
        }
        if let target {
            try commands.command(commandTarget(target))
        }
        return favorState()
    }

    func followerDebug(_ command: AgentDebugCommand) throws(AgentFailure) -> AgentJSON {
        switch command {
        case let .favor(reference, target, exit):
            try commandFollower(reference, target: target, exit: exit)
        case let .teammate(reference, on):
            try setTeammate(reference, on: on)
        case let .relationship(reference, rank):
            try setRelationship(reference, rank: Int8(rank))
        default:
            throw AgentFailure(.invalidArgument, "not a follower command")
        }
    }

    private func setTeammate(_ reference: String, on: Bool) throws(AgentFailure) -> AgentJSON {
        let resolved = try resolveReference(reference)
        guard let bridge = game.scripts.bridge else { throw notReady() }
        bridge.updateScriptedState(of: resolved.key) {
            $0.setFlag(ScriptedStateName.playerTeammate, on)
        }
        let flag = bridge.scriptedState(of: resolved.key).flag(ScriptedStateName.playerTeammate)
        return ["ref": .string(reference), "teammate": .bool(flag == true)]
    }

    /// The reply shows `firstFriendRank`, which fixes the item allowance of a friend.
    private func setRelationship(
        _ reference: String,
        rank: Int8
    ) throws(AgentFailure) -> AgentJSON {
        let resolved = try resolveReference(reference)
        guard let relationships = game.factions.relationships else { throw notReady() }
        relationships.setRank(rank, of: resolved.key, toward: .player)
        let state = relationships.state(of: .player)
        return [
            "ref": .string(reference),
            "rank": state.rank(toward: resolved.key).map { .init(Int($0)) } ?? .null,
            "firstFriendRank": state.firstFriendRank(toward: resolved.key)
                .map { .init(Int($0)) } ?? .null
        ]
    }

    /// A reference, or `x,y,z` for a spot on the ground.
    private func commandTarget(_ text: String) throws(AgentFailure) -> FollowerCommandTarget? {
        let numbers = text.split(separator: ",").compactMap { Float($0) }
        if numbers.count == 3 {
            let point = SIMD3(numbers[0], numbers[1], numbers[2])
            return FollowerCommandTarget(key: nil, kind: .ground, position: point)
        }
        return try game.followerCommandWorld.commandTarget(resolveReference(text).key)
    }

    private static func phaseName(_ phase: FollowerCommandPhase) -> String {
        switch phase {
        case .idle: "idle"
        case .choosing: "choosing"
        case .walking: "walking"
        case .waiting: "waiting"
        }
    }

    private func decisionJSON(_ decision: FollowerCommandDecision) -> AgentJSON {
        var json: [String: AgentJSON] = ["line": .string(decision.line.description)]
        switch decision {
        case let .agree(task): json["task"] = taskJSON(task)
        case let .refuse(reason): json["refusal"] = .string(reason.rawValue)
        case let .moralRefusal(crime): json["crime"] = .string(crime.rawValue)
        }
        return .object(json)
    }

    private func taskJSON(_ task: FollowerCommandTask) -> AgentJSON {
        [
            "action": .string(task.action.rawValue),
            "target": task.target.key.flatMap(formID) ?? .null,
            "position": .init(task.target.position),
            "kind": .string(task.target.kind.rawValue),
            "unlocks": .bool(task.unlocks),
            "crime": task.crime.map { .string($0.rawValue) } ?? .null
        ]
    }
}
