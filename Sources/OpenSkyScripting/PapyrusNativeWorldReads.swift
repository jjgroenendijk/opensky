// Reads of loaded world state: whether a cell is an interior (Creation Kit wiki
// "IsInterior - Cell"), who an actor talks to ("GetDialogueTarget - Actor"), and the gold
// an actor asks as a bribe, priced as `GetBribeSuccess` prices it, and a reference's size.

import Foundation
import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyDialogueInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyScriptingInterface
import OpenSkyWorldState

extension PapyrusNativeFunctions {
    static func installWorldReads(into registry: inout PapyrusNativeRegistry) {
        scriptState("Cell", "IsInterior", into: &registry) { call, bridge, key in
            guard
                let word = bridge.loadOrderWord(of: key),
                let interior = bridge.conditionData?().isInterior(cell: FormID(word))
            else { return failure(call, "IsInterior needs a loaded cell") }
            return .returned(.boolean(interior))
        }
        // Only the player's conversation is modelled; the game returns None on the player.
        scriptState("Actor", "GetDialogueTarget", into: &registry) { call, bridge, key in
            guard let world = bridge.world, let evaluator = bridge.conditionEvaluator?() else {
                return needsWorld(call)
            }
            guard key != .player, evaluator.context.dialogue.speakerInDialogue == key else {
                return .returned(.none)
            }
            return .returned(.object(world.objectHandle(for: .player)))
        }
        // The `OBND` box of the base along X, Y, and Z, times the reference's scale.
        for (name, axis) in [("GetWidth", 0), ("GetLength", 1), ("GetHeight", 2)] {
            scriptState("ObjectReference", name, into: &registry) { call, bridge, key in
                guard
                    case let .plugin(plugin, objectID) = bridge.resolvedBase(of: key),
                    let bounds = bridge.keywordStore?.bounds(
                        of: ResolvedFormID(plugin: plugin, objectID: objectID)
                    )
                else { return failure(call, "\(name) needs a base form with bounds") }
                let size = Float(bounds.maximum[axis]) - Float(bounds.minimum[axis])
                let scale = bridge.referenceState(for: key)?.transform.scale ?? 1
                return .returned(.float(size * scale))
            }
        }
        scriptState("Actor", "GetBribeAmount", into: &registry) { call, bridge, key in
            guard let amount = bridge.conditionEvaluator?().context.bribeAmount(of: key) else {
                return failure(call, "GetBribeAmount needs both actors' values and the settings")
            }
            return .returned(.integer(Int32(min(max(amount, 0), 1_000_000_000))))
        }
    }
}
