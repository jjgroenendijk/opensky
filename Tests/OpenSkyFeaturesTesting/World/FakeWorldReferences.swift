// A fixed reference index that stands in for the cell streamer in tests.

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldInterface
import OpenSkyWorldState

/// Synthetic `PapyrusWorldReferenceSource`: a fixed reference index that
/// answers as if every entry were resident in one cell. This is what lets a
/// test run with no `CellStreamer`, no scene, and no GPU.
nonisolated public final class FakeWorldReferences: PapyrusWorldReferenceSource {
    /// The cell every reference reports when a caller names none.
    public static let defaultCell = CellSceneLocation.exterior(CellCoordinate(x: 0, y: 0))

    public var index: RuntimeReferenceIndex
    /// Cell every known reference reports as resident in; nil models a
    /// reference the streamer cannot attribute, so writes go unattributed.
    public var cell: CellSceneLocation?
    /// Plugin records of references no resident cell holds.
    public var pluginPlacements: [ReferenceKey: PluginPlacement] = [:]

    public init(
        entries: [RuntimeReferenceEntry],
        cell: CellSceneLocation? = FakeWorldReferences.defaultCell
    ) {
        index = RuntimeReferenceIndex(entries: entries)
        self.cell = cell
    }

    public func referenceEntry(formID: FormID) -> RuntimeReferenceEntry? {
        index.entry(for: formID)
    }

    public func referenceEntry(key: ReferenceKey) -> RuntimeReferenceEntry? {
        index[key]
    }

    public func cellLocation(of key: ReferenceKey) -> CellSceneLocation? {
        index[key] == nil ? nil : cell
    }

    public func activateChildren(of key: ReferenceKey) -> [ReferenceKey] {
        index[key].map { index.sortedEntries().activateChildren(of: $0.formID) } ?? []
    }

    public func pluginPlacement(of key: ReferenceKey) -> PluginPlacement? {
        pluginPlacements[key]
    }
}
