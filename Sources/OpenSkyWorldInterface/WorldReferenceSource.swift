import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

/// Decoded references and their resident cell, as the bridge needs them.
///
/// Nonisolated because `CellStreamer` is: the bridge only ever calls it from
/// the main actor, on the same thread that drives `draw(in:)`.
nonisolated public protocol PapyrusWorldReferenceSource: AnyObject {
    func referenceEntry(formID: FormID) -> RuntimeReferenceEntry?
    func referenceEntry(key: ReferenceKey) -> RuntimeReferenceEntry?
    /// Cell the reference is currently resident in, or nil when nothing
    /// resident holds it. A write attributed to a cell rebuilds that cell
    /// alone; nil rebuilds every resident cell.
    func cellLocation(of key: ReferenceKey) -> CellSceneLocation?
    /// Resident references whose `XAPR` names `key`: activating `key` activates them too.
    func activateChildren(of key: ReferenceKey) -> [ReferenceKey]
    /// The plugin record behind `key` and the cell that draws it there, loaded or not.
    func pluginPlacement(of key: ReferenceKey) -> PluginPlacement?
}

nonisolated extension PapyrusWorldReferenceSource {
    public func pluginPlacement(of _: ReferenceKey) -> PluginPlacement? {
        nil
    }
}

/// A placed record and its plugin cell, as `MoveTo` needs them for an unloaded reference.
nonisolated public struct PluginPlacement: Sendable {
    public let entry: RuntimeReferenceEntry
    public let home: CellSceneLocation

    public init(entry: RuntimeReferenceEntry, home: CellSceneLocation) {
        self.entry = entry
        self.home = home
    }
}

nonisolated extension Sequence<RuntimeReferenceEntry> {
    /// The entries whose `XAPR` activate parents include `parent`, in sequence order.
    public func activateChildren(of parent: FormID) -> [ReferenceKey] {
        compactMap { entry in
            let details = entry.placedReference?.details ?? entry.placedActor?.details
            let linked = details?.activateParents.contains { $0.reference == parent } ?? false
            return linked ? entry.key : nil
        }
    }
}
