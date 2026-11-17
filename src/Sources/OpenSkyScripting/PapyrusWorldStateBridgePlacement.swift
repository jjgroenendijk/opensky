// Where a reference is, loaded or not, and how `MoveTo` moves it between cells.
// A resident reference answers from its cell; an unloaded one from its plugin
// record with this session's deltas on top.

import Foundation
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyScriptingInterface
import OpenSkyWorldInterface
import OpenSkyWorldState

extension PapyrusWorldStateBridge.Placements {
    public func placement(of key: ReferenceKey) -> ReferencePlacement? {
        if let state = bridge.referenceState(for: key) {
            let location = bridge.cellLocation(of: key)
            return ReferencePlacement(
                state: state, location: location, worldspace: residentWorldspace(of: location)
            )
        }
        guard let plugin = bridge.ports.references?.pluginPlacement(of: key) else { return nil }
        let delta = bridge.worldState.delta(for: key)
        let state = ReferenceState(baseline: plugin.entry).applying(delta)
        guard let moved = delta?.component(ReferenceRelocation.self) else {
            return ReferencePlacement(
                state: state, location: plugin.home, worldspace: plugin.worldspace
            )
        }
        return ReferencePlacement(
            state: state, location: moved.location, worldspace: moved.worldspace
        )
    }

    /// The resident worldspace for a resident exterior cell; nil for an interior.
    private func residentWorldspace(of location: CellSceneLocation?) -> String? {
        guard case .exterior = location else { return nil }
        return bridge.ports.references?.residentWorldspace
    }

    /// A new reference of `base` where `anchor` stands, facing its way. It is a spawn, so
    /// the save keeps it and the cell build places it, an actor included. Nil when the
    /// base has no load-order FormID or the anchor has no cell.
    public func spawnReference(of base: ReferenceKey, at anchor: ReferenceKey) -> ReferenceKey? {
        guard
            case let .plugin(name, objectID) = base,
            let formID = bridge.formIDResolver?.localFormID(
                of: ResolvedFormID(plugin: name, objectID: objectID)
            ),
            let placement = placement(of: anchor),
            let location = placement.location
        else { return nil }
        let spawn = ReferenceSpawnState(
            base: formID, location: location, placement: placement.state.transform.placement
        )
        let key = bridge.worldState.allocateGeneratedKey()
        bridge.worldState.set(spawn, for: key, in: location)
        return key
    }

    /// Sends `key` to `location` of the resident worldspace.
    public func relocate(_ key: ReferenceKey, to location: CellSceneLocation) {
        relocate(key, to: location, worldspace: residentWorldspace(of: location))
    }

    /// Sends `key` to `location` of `worldspace`, nil for an interior. Moving it back to its
    /// plugin cell drops the move.
    public func relocate(
        _ key: ReferenceKey, to location: CellSceneLocation, worldspace: String?
    ) {
        let origin = placement(of: key)?.location
        let moved = ReferenceRelocation(location: location, worldspace: worldspace)
        let home = bridge.ports.references?.pluginPlacement(of: key)
        if let home, moved.lands(in: home.home, worldspace: home.worldspace) {
            bridge.worldState.reset(.relocation, for: key)
        } else {
            bridge.worldState.set(moved, for: key, in: location)
        }
        queueCellAttachmentChange(of: key, from: origin, to: location)
    }

    /// `OnAttachedToCell` or `OnDetachedFromCell` when a move crosses between an attached
    /// and a detached cell (<https://ck.uesp.net/wiki/OnAttachedToCell_-_ObjectReference>).
    private func queueCellAttachmentChange(
        of key: ReferenceKey, from origin: CellSceneLocation?, to destination: CellSceneLocation
    ) {
        guard let world = bridge.world, key != bridge.playerKey else { return }
        let wasAttached = origin.map { world.attachedByCell[$0] != nil } ?? false
        let isAttached = world.attachedByCell[destination] != nil
        guard wasAttached != isAttached else { return }
        let name = isAttached
            ? PapyrusEngineEvents.onAttachedToCell : PapyrusEngineEvents.onDetachedFromCell
        _ = world.scriptEvents.queueActorEvent(name, on: key, arguments: [])
    }
}
