// The light of the cell the game draws the main menu's logo in: the DOBJ `MMCL`
// default object, `MainMenuCell` in Skyrim.esm. See docs/engine/main-menu.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public struct MainMenuCellLighting: Equatable, Sendable {
    public static let defaultObjectTag = "MMCL"

    /// The cell's own `XCLL`.
    public let cell: CellLightingValues?
    /// The `LGTM` its `LTMP` names, for the fields the cell inherits.
    public let template: CellLightingValues?

    public init(cell: CellLightingValues?, template: CellLightingValues?) {
        self.cell = cell
        self.template = template
    }

    /// Nil when no plugin names a main menu cell, or the cell does not decode.
    public init?(loadOrder: LoadOrderPlugins, defaultObjects: DefaultObjectStore) {
        guard
            let id = defaultObjects.object(tag: Self.defaultObjectTag),
            let formID = loadOrder.space.localFormID(of: id),
            let found = loadOrder.record(withFormID: formID),
            found.record.type == "CELL",
            let cell = try? found.decode({ try Cell(record: $0, localized: found.localized) })
        else { return nil }
        let template = cell.lightingTemplate
            .flatMap { loadOrder.record(withFormID: $0) }
            .flatMap { found in try? found.decode { try LightingTemplate(record: $0) } }
        self.init(cell: cell.lighting, template: template?.values)
    }
}
