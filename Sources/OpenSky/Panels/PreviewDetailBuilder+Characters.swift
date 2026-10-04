// Character readouts in the Asset Browser: a body-part record's nodes checked
// against its skeleton, and a Havok tagfile's census with its bone binding.

import Foundation
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyPreview

nonisolated extension PreviewDetailBuilder {
    private static let characterSkeleton =
        "meshes\\actors\\character\\character assets\\skeleton.hkx"

    /// The node table of a `BPTD`, or nil for any other record.
    func bodyPartNodes(_ preview: PreviewRecord) -> String? {
        guard
            preview.record.type == "BPTD",
            let data = try? BodyPartData(record: preview.record, localized: preview.localized)
        else { return nil }
        let parts = data.parts.compactMap { part in
            part.nodeName.map { (part: RecordTextDump.nameText(part.name), node: $0) }
        }
        let skeleton = data.model.flatMap { model in
            (try? NIFFile(data: fileSystem.contents(forPath: "meshes\\" + model.path)))
                .flatMap { try? NIFNodeHierarchy(file: $0) }
                .map { Set($0.names.values) }
        }
        return AssetInfoText.bodyPartNodes(parts, skeleton: skeleton)
    }

    func tagfileText(_ data: Data) -> String {
        do {
            let census = try HKTCensus(file: HKTagfile(data: data))
            let skeleton = (try? HKASkeleton.skeletons(
                in: HKXFile(data: fileSystem.contents(forPath: Self.characterSkeleton))
            )).map { Set($0.flatMap(\.boneNames)) }
            return AssetInfoText.tagfile(census, skeleton: skeleton)
        } catch {
            return "[ERROR] tagfile parse failed: \(String(describing: error))"
        }
    }
}
