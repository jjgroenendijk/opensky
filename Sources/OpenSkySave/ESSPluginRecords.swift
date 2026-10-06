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

    public let loadOrder: [String]
    var forms: [Key: Form] = [:]
    /// Placed reference -> its base form, for the references the save changed.
    var referenceBases: [Key: ResolvedFormID] = [:]
    var scriptVariables: [String: [String: String]] = [:]
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
        index.form(form).map { String(describing: $0.signature) }
    }

    public func editorID(of form: ResolvedFormID) -> String? {
        index.form(form)?.editorID
    }

    public func globalType(of form: ResolvedFormID) -> Global.ValueType? {
        index.form(form)?.globalType
    }

    public func race(editorID: String) -> ResolvedFormID? {
        let wanted = editorID.lowercased()
        let match = index.forms.first { _, form in
            form.signature == "RACE" && form.editorID?.lowercased() == wanted
        }
        return match.map {
            ResolvedFormID(plugin: index.canonicalName($0.key.plugin), objectID: $0.key.objectID)
        }
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
