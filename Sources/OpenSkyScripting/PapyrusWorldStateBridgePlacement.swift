// Where a reference is, loaded or not, and how `MoveTo` moves it between cells.
// A resident reference answers from its cell; an unloaded one from its plugin
// record with this session's deltas on top.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldInterface
import OpenSkyWorldState

/// A reference's current state and the cell that draws it.
public struct ReferencePlacement {
    public let state: ReferenceState
    public let location: CellSceneLocation?
}

extension PapyrusWorldStateBridge {
    public func placement(of key: ReferenceKey) -> ReferencePlacement? {
        if let state = referenceState(for: key) {
            return ReferencePlacement(state: state, location: cellLocation(of: key))
        }
        guard let plugin = references?.pluginPlacement(of: key) else { return nil }
        let delta = worldState.delta(for: key)
        let state = ReferenceState(baseline: plugin.entry).applying(delta)
        let moved = delta?.component(ReferenceRelocation.self)?.location
        return ReferencePlacement(state: state, location: moved ?? plugin.home)
    }

    /// A new reference of `base` where `anchor` stands, facing its way. It is a spawn, so
    /// the save keeps it and the cell build places it, an actor included. Nil when the
    /// base has no load-order FormID or the anchor has no cell.
    public func spawnReference(of base: ReferenceKey, at anchor: ReferenceKey) -> ReferenceKey? {
        guard
            case let .plugin(name, objectID) = base,
            let formID = formIDResolver?.localFormID(
                of: ResolvedFormID(plugin: name, objectID: objectID)
            ),
            let placement = placement(of: anchor),
            let location = placement.location
        else { return nil }
        let spawn = ReferenceSpawnState(
            base: formID, location: location, placement: placement.state.transform.placement
        )
        let key = worldState.allocateGeneratedKey()
        worldState.set(spawn, for: key, in: location)
        return key
    }

    /// Sends `key` to `location`. Moving it back to its plugin cell drops the move.
    public func relocate(_ key: ReferenceKey, to location: CellSceneLocation) {
        let home = references?.pluginPlacement(of: key)?.home
        if home == location {
            worldState.reset(.relocation, for: key)
        } else {
            worldState.set(ReferenceRelocation(location: location), for: key, in: location)
        }
    }
}
