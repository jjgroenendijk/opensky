// A load order of named forms in place of real plugins, for import tests.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
@testable import OpenSkySave

struct FakeESSImportRecords: ESSImportRecords {
    struct Form {
        let signature: String
        var editorID: String?
        var globalType: Global.ValueType?
    }

    var loadOrder = ["Skyrim.esm", "Update.esm"]
    /// Keyed by lowercased plugin and object id.
    var forms: [String: Form] = [:]
    var baselines: [ReferenceKey: ReferenceInventoryState] = [:]
    var scripts: [String: [String: String]] = [:]

    mutating func add(
        _ plugin: String, _ objectID: UInt32, _ signature: String, editorID: String? = nil,
        globalType: Global.ValueType? = nil
    ) {
        forms[Self.name(plugin, objectID)] = Form(
            signature: signature, editorID: editorID, globalType: globalType
        )
    }

    private static func name(_ plugin: String, _ objectID: UInt32) -> String {
        "\(plugin.lowercased()):\(objectID)"
    }

    private func form(_ resolved: ResolvedFormID) -> Form? {
        forms[Self.name(resolved.plugin, resolved.objectID)]
    }

    func signature(of form: ResolvedFormID) -> String? {
        self.form(form)?.signature
    }

    func editorID(of form: ResolvedFormID) -> String? {
        self.form(form)?.editorID
    }

    func globalType(of form: ResolvedFormID) -> Global.ValueType? {
        self.form(form)?.globalType
    }

    func race(editorID: String) -> ResolvedFormID? {
        forms.first { $0.value.signature == "RACE" && $0.value.editorID == editorID }
            .flatMap { entry in
                let parts = entry.key.split(separator: ":")
                return UInt32(parts[1])
                    .map { ResolvedFormID(plugin: String(parts[0]), objectID: $0) }
            }
    }

    func cellLocation(space: ResolvedFormID, position: SIMD3<Float>) -> CellSceneLocation? {
        signature(of: space) == "CELL" ? .interior(FormID(space.objectID)) : nil
    }

    func baselineInventory(of reference: ReferenceKey) -> ReferenceInventoryState {
        baselines[reference] ?? .empty
    }

    func declaredVariables(ofScript name: String) -> [String: String]? {
        scripts[name.lowercased()]
    }
}
