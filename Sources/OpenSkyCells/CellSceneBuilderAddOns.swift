// Add-on nodes in a cell build: each `BSValueNode` of a placed mesh names an
// `ADDN` record by its `DATA` index, and the game copies that record's model to
// the node (https://ck.uesp.net/wiki/AddOnNode). Layout: docs/formats/nif.md.

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyRendering
import simd

nonisolated extension CellSceneBuilder {
    /// The add-on models of `instances`, each placed at its node.
    func addOnInstances(for instances: [ResolvedInstance]) -> [ResolvedInstance] {
        let plain = ModelSurfaceOverride(diffuseTexture: nil, normalTexture: nil, tint: nil)
        var added: [ResolvedInstance] = []
        for instance in instances {
            let nodes = meshes.addOnNodes(forPath: instance.modelPath)
            guard !nodes.isEmpty else { continue }
            let models = addOnModelIndexBuildingIfNeeded()
            for node in nodes {
                guard
                    let path = models[node.index],
                    let model = try? meshes.model(path: path)
                else { continue }
                added.append(ResolvedInstance(
                    sortKey: (try? VirtualFileSystem.normalize(path)) ?? path,
                    formID: instance.formID,
                    modelPath: path,
                    model: model,
                    surface: plain,
                    transform: instance.transform * node.transform
                ))
            }
        }
        return added
    }

    func addOnModelIndexBuildingIfNeeded() -> [UInt32: String] {
        if let addOnModelIndex {
            return addOnModelIndex
        }
        let records = loadOrderRecords(of: "ADDN") { record, _ in try AddonNode(record: record) }
        var index: [UInt32: String] = [:]
        for record in records.values.sorted(by: { $0.formID.rawValue < $1.formID.rawValue }) {
            guard let nodeIndex = record.nodeIndex, let path = record.model?.path else { continue }
            index[nodeIndex] = index[nodeIndex] ?? path
        }
        addOnModelIndex = index
        return index
    }
}
