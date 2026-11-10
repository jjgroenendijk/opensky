// The port an `.ess` import reads the installed plugins through. The app and the CLI
// answer it from their game data; tests pass a fake. See docs/engine/ess-import.md.

import Foundation
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyInventoryInterface

nonisolated public protocol ESSImportRecords {
    /// The plugins loaded now, in load order.
    var loadOrder: [String] { get }
    /// The light plugins among `loadOrder`, which take `0xFE` slots.
    var lightPlugins: Set<String> { get }
    /// The record type of a form in the current load order, such as `QUST`.
    func signature(of form: ResolvedFormID) -> String?
    func editorID(of form: ResolvedFormID) -> String?
    /// The value type of a `GLOB`, nil for any other form.
    func globalType(of form: ResolvedFormID) -> Global.ValueType?
    func race(editorID: String) -> ResolvedFormID?
    /// Where a created reference sits: an interior cell, or the exterior cell of a
    /// worldspace or exterior `CELL` at `position`.
    func cellLocation(space: ResolvedFormID, position: SIMD3<Float>) -> CellSceneLocation?
    /// What the reference holds before any change, which `.ess` inventory counts adjust.
    func baselineInventory(of reference: ReferenceKey) -> ReferenceInventoryState
    /// Lowercased variable name -> lowercased declaring script, inherited ones included.
    /// Nil when no compiled script has the name.
    func declaredVariables(ofScript name: String) -> [String: String]?
}

/// Where the save left the player.
nonisolated public struct ESSImportedPlacement: Equatable, Sendable {
    /// A worldspace or an interior cell.
    let space: ResolvedFormID
    public let isInterior: Bool
    public let spaceEditorID: String?
    public let position: SIMD3<Float>
    /// The facing, radians, from the player's reference change when it has one.
    let heading: Float?
    /// The exterior cell the save names, if any.
    let cell: SIMD2<Int32>?
}
