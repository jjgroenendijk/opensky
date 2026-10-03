// Asset Browser text for character data: the nodes of a body-part record
// checked against its skeleton, and the census of a Havok tagfile.
// See docs/formats/body-parts.md and docs/formats/hkt-tagfile.md.

import Foundation
import OpenSkyFormatsAnimation

nonisolated extension AssetInfoText {
    /// One line per body part. `skeleton` is nil when the skeleton did not load.
    public static func bodyPartNodes(
        _ parts: [(part: String, node: String)],
        skeleton: Set<String>?
    ) -> String {
        guard let skeleton else {
            return (["Nodes: skeleton not loaded"] + parts.map { "\($0.part): \($0.node)" })
                .joined(separator: "\n")
        }
        let found = parts.count { skeleton.contains($0.node) }
        return (["Nodes: \(found) of \(parts.count) found in the skeleton"] + parts.map {
            "\($0.part): \($0.node) · " + (skeleton.contains($0.node) ? "found" : "missing")
        }).joined(separator: "\n")
    }

    public static func tagfile(_ census: HKTCensus, skeleton: Set<String>?) -> String {
        var lines = ["Havok tagfile version \(census.version), end tag \(census.hasEndTag)"]
        lines += census.definitions.map {
            "class \($0.name) v\($0.version): \(census.objectCounts[$0.name] ?? 0) objects"
        }
        lines.append("Cloth classes: \(census.clothClasses.count)")
        lines.append(boneBinding(census.skeletonBones, skeleton: skeleton))
        return lines.joined(separator: "\n")
    }

    /// Which bones a tagfile names that the character skeleton also has.
    public static func boneBinding(_ bones: [String], skeleton: Set<String>?) -> String {
        guard !bones.isEmpty else { return "Bones: none" }
        guard let skeleton else { return "Bones: \(bones.count), skeleton not loaded" }
        let misses = bones.filter { !skeleton.contains($0) }
        let head = "Bones: \(bones.count - misses.count) of \(bones.count) bind to the skeleton"
        return misses.isEmpty ? head : head + "\nMissing: " + misses.joined(separator: ", ")
    }
}
