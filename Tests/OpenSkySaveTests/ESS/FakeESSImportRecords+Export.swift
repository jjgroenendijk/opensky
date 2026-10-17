// The fake load order answering the export port as well, so one fake drives a round trip.

import Foundation
import OpenSkyFormatsESM
@testable import OpenSkySave

extension FakeESSImportRecords: ESSExportRecords {
    var plugins: [ESSExportPlugin] {
        loadOrder.map { ESSExportPlugin(name: $0, isLight: lightPlugins.contains($0)) }
    }

    func form(editorID: String, signature: String) -> ResolvedFormID? {
        let match = forms.first { $0.value.signature == signature && $0.value.editorID == editorID }
        return match.flatMap { entry in
            let parts = entry.key.split(separator: ":")
            let plugin = loadOrder.first { $0.lowercased() == parts[0] } ?? String(parts[0])
            return UInt32(parts[1]).map { ResolvedFormID(plugin: plugin, objectID: $0) }
        }
    }

    func recordFlags(of reference: ResolvedFormID) -> UInt32? {
        placed[Self.name(reference.plugin, reference.objectID)]?.flags
    }

    func placementSpace(of reference: ResolvedFormID) -> ResolvedFormID? {
        placed[Self.name(reference.plugin, reference.objectID)]?.space
    }

    func script(named name: String) -> ESSExportScript? {
        exportScripts[name.lowercased()]
    }
}
