// The location a built cell belongs to: its `XLCN` link, else the location whose cell
// list holds the exterior cell. See docs/formats/locations.md#cell-link.

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

nonisolated public struct CellLocationResolver: Sendable {
    public let store: LocationStore
    private let cells: LocationCellMap

    public init(store: LocationStore) {
        self.store = store
        cells = LocationCellMap(store: store)
    }

    public func location(of scene: CellScene) -> ResolvedFormID? {
        if
            let link = scene.locationLink,
            let plugin = scene.ownerPluginName,
            let linked = store.resolvedID(link, fromPlugin: plugin)
        {
            return linked
        }
        guard
            case let .exterior(coordinate)? = scene.location,
            let worldspace = scene.worldspace.flatMap({
                store.resolvedID($0, fromPlugin: FormIDResolver.loadOrderSpaceName)
            })
        else { return nil }
        return cells.location(worldspace: worldspace, x: coordinate.x, y: coordinate.y)
    }

    /// Where each reference in `scenes` is, by the cell that holds it.
    public func referenceLocations(in scenes: [CellScene]) -> [ReferenceKey: ResolvedFormID] {
        var result: [ReferenceKey: ResolvedFormID] = [:]
        for scene in scenes {
            guard let location = location(of: scene) else { continue }
            for entry in scene.references.sortedEntries() {
                result[entry.key] = location
            }
        }
        return result
    }
}
