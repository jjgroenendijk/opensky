// The installed plugins as an `ESSImportRecords`. The index is built for one save: it
// holds only the record types the import checks, the bases of the references the save
// changed, and the scripts its Papyrus table names. See docs/engine/ess-import.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface

nonisolated public struct ESSPluginIndex: Sendable {
    struct Key: Hashable, Sendable {
        let plugin: String
        let objectID: UInt32

        init(_ form: ResolvedFormID) {
            plugin = form.plugin.lowercased()
            objectID = form.objectID
        }
    }

    struct Form: Sendable {
        let signature: FourCC
        var editorID: String?
        var globalType: Global.ValueType?
        var isExteriorCell = false
    }

    /// A placed reference as its plugin stores it.
    struct Placed: Sendable {
        let signature: FourCC
        let flags: UInt32
        /// Its interior cell, or its exterior worldspace.
        let space: ResolvedFormID?
    }

    public let loadOrder: [String]
    var forms: [Key: Form] = [:]
    /// Placed reference -> its base form, for the references the save changed.
    var referenceBases: [Key: ResolvedFormID] = [:]
    var scriptVariables: [String: [String: String]] = [:]
    var placedReferences: [Key: Placed] = [:]
    /// Lowercased names of ESL-flagged plugins.
    var lightPlugins: Set<String> = []
    /// Lowercased script name -> its own variables, for an export.
    var exportScripts: [String: ESSExportScript] = [:]
    let currentResolver: FormIDResolver

    init(loadOrder: [String]) {
        self.loadOrder = loadOrder
        currentResolver = FormIDResolver.loadOrder(loadOrder)
    }

    func form(_ id: ResolvedFormID) -> Form? {
        forms[Key(id)]
    }

    func canonicalName(_ lowercased: String) -> String {
        loadOrder.first { $0.lowercased() == lowercased } ?? lowercased
    }
}

/// The index plus the inventory baselines, which live with the running world.
nonisolated public struct ESSPluginRecords: ESSImportRecords {
    public let index: ESSPluginIndex
    let baselines: InventoryBaselineResolver?

    public init(index: ESSPluginIndex, baselines: InventoryBaselineResolver? = nil) {
        self.index = index
        self.baselines = baselines
    }

    public var loadOrder: [String] {
        index.loadOrder
    }

    public func signature(of form: ResolvedFormID) -> String? {
        (index.form(form)?.signature ?? index.placedReferences[ESSPluginIndex.Key(form)]?.signature)
            .map { String(describing: $0) }
    }

    public func editorID(of form: ResolvedFormID) -> String? {
        index.form(form)?.editorID
    }

    public func globalType(of form: ResolvedFormID) -> Global.ValueType? {
        index.form(form)?.globalType
    }

    public func race(editorID: String) -> ResolvedFormID? {
        form(editorID: editorID, signature: "RACE")
    }

    /// Exterior cells are 4096 units wide, as in the plugins' `XCLC` grid.
    public func cellLocation(space: ResolvedFormID, position: SIMD3<Float>) -> CellSceneLocation? {
        guard let form = index.form(space) else { return nil }
        if form.signature == "CELL", !form.isExteriorCell {
            return index.currentResolver.localFormID(of: space).map(CellSceneLocation.interior)
        }
        return .exterior(CellCoordinate(
            x: Int32((position.x / 4096).rounded(.down)),
            y: Int32((position.y / 4096).rounded(.down))
        ))
    }

    public func baselineInventory(of reference: ReferenceKey) -> ReferenceInventoryState {
        guard
            let baselines, case let .plugin(name, objectID) = reference,
            let base = index.referenceBases[ESSPluginIndex.Key(
                ResolvedFormID(plugin: name, objectID: objectID)
            )],
            let baseID = index.currentResolver.localFormID(of: base),
            let signature = index.form(base)?.signature
        else { return .empty }
        switch signature {
        case "CONT": return baselines.baseline(for: .container(base: baseID))
        case "NPC_": return baselines.baseline(for: .actor(base: baseID))
        default: return .empty
        }
    }

    public func declaredVariables(ofScript name: String) -> [String: String]? {
        index.scriptVariables[name.lowercased()]
    }
}
