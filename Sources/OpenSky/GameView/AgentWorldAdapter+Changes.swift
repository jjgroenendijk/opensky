// `openskycli game state changes`: the newest world-state writes, so a check can see
// which reference keeps a cell rebuilding (docs/engine/runtime-state.md).

import OpenSkyAgentControl
import OpenSkyCells
import OpenSkyFormatsESM
import OpenSkyWorld
import OpenSkyWorldState

extension AgentWorldAdapter {
    func changesState(limit: Int) -> AgentJSON {
        let entries = game.worldState.journalEntries.suffix(max(0, limit))
        var fields: [String: AgentJSON] = [
            "changes": .array(entries.map(change))
        ]
        if let streamer = game.streamer {
            fields["transitionInFlight"] = streamer.transitionInFlight
                .map { .formID($0.rawValue) } ?? .null
            fields["interiorRebuilding"] = .bool(streamer.interiorRebuildInFlight)
            fields["interiorMutationSequence"] = .init(Int(streamer.interiorMutationSequence))
            fields["interiorSceneSequence"] = streamer.interiorScene
                .map { .init(Int($0.stateSequence)) } ?? .null
        }
        return .object(fields)
    }

    private func change(_ entry: WorldStateJournalEntry) -> AgentJSON {
        let formID = game.streamer?.referenceEntry(key: entry.key)?.formID
        return [
            "sequence": .init(Int(entry.sequence)),
            "ref": formID.map { .formID($0.rawValue) } ?? .string(String(describing: entry.key)),
            "kind": .string(entry.kind.rawValue),
            "reset": .bool(entry.isReset)
        ]
    }
}
