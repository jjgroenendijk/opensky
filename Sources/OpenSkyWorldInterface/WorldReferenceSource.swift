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
}
