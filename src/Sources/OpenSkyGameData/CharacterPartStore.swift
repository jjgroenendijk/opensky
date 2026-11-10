// Head parts, colors, eyes, and body-part data across the load order. Extra
// parts expand without looping on a cycle. See docs/formats/head-parts.md and
// docs/formats/body-parts.md.

import Foundation
import OpenSkyFormatsCore
public import OpenSkyFormatsESM

/// A head part with its extra parts, depth first. `cycles` counts links back to a part already
/// seen.
nonisolated struct ExpandedHeadParts: Sendable {
    let parts: [ResolvedRecord<HeadPart>]
    let cycles: Int
    let danglingLinks: Int
}

/// BPTD node names checked against the node names of a skeleton.
nonisolated struct BodyPartNodeResolution: Equatable, Sendable {
    let hits: [String]
    let misses: [String]
}

nonisolated struct CharacterPartStore: Sendable {
    static let types: Set<FourCC> = ["HDPT", "CLFM", "EYES", "BPTD"]

    let headParts: TypedRecordStore<HeadPart>
    let colors: TypedRecordStore<ColorForm>
    let eyes: TypedRecordStore<Eyes>
    let bodyParts: TypedRecordStore<BodyPartData>
    private let partsByType: [HeadPart.PartType: [ResolvedFormID]]

    init(index: RecordIndex) {
        headParts = TypedRecordStore(
            index: index, types: ["HDPT"],
            decode: { try HeadPart(record: $0.record, localized: $0.localized) },
            editorID: \.editorID
        )
        colors = TypedRecordStore(
            index: index, types: ["CLFM"],
            decode: { try ColorForm(record: $0.record, localized: $0.localized) },
            editorID: \.editorID
        )
        eyes = TypedRecordStore(
            index: index, types: ["EYES"],
            decode: { try Eyes(record: $0.record, localized: $0.localized) },
            editorID: \.editorID
        )
        bodyParts = TypedRecordStore(
            index: index, types: ["BPTD"],
            decode: { try BodyPartData(record: $0.record, localized: $0.localized) },
            editorID: \.editorID
        )
        var partsByType: [HeadPart.PartType: [ResolvedFormID]] = [:]
        for part in headParts.records {
            guard let type = part.record.partType else { continue }
            partsByType[type, default: []].append(part.id)
        }
        self.partsByType = partsByType
    }

    init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(plugins: plugins, recordTypes: Self.types))
    }

    func headParts(ofType type: HeadPart.PartType) -> [ResolvedRecord<HeadPart>] {
        (partsByType[type] ?? []).compactMap { headParts.record($0) }
    }

    func expandedParts(_ id: ResolvedFormID) -> ExpandedHeadParts {
        var parts: [ResolvedRecord<HeadPart>] = []
        var seen: Set<ResolvedFormID> = []
        var cycles = 0
        var dangling = 0
        var stack = [id]
        while let next = stack.popLast() {
            guard seen.insert(next).inserted else {
                cycles += 1
                continue
            }
            guard let part = headParts.record(next) else {
                dangling += 1
                continue
            }
            parts.append(part)
            let extras = part.record.extraParts.compactMap {
                headParts.index.resolvedID($0, fromPlugin: part.sourcePlugin)
            }
            stack.append(contentsOf: extras.reversed())
        }
        return ExpandedHeadParts(parts: parts, cycles: cycles, danglingLinks: dangling)
    }

    /// The CLFM of a head part's CNAM.
    func color(of part: ResolvedRecord<HeadPart>) -> ResolvedRecord<ColorForm>? {
        colors.resolve(part.record.color, fromPlugin: part.sourcePlugin)
    }

    /// The CLFM of an NPC_ HCLF, read from the plugin that authored the actor.
    func hairColor(
        of actor: ActorBase,
        fromPlugin pluginName: String
    ) -> ResolvedRecord<ColorForm>? {
        colors.resolve(actor.details.hairColor, fromPlugin: pluginName)
    }

    /// Compares node names without case, as the game's skeleton lookup does.
    static func resolveNodes(
        of data: BodyPartData,
        skeletonNodes: Set<String>
    ) -> BodyPartNodeResolution {
        let known = Set(skeletonNodes.map { $0.lowercased() })
        let names = data.parts.compactMap(\.nodeName)
        return BodyPartNodeResolution(
            hits: names.filter { known.contains($0.lowercased()) },
            misses: names.filter { !known.contains($0.lowercased()) }
        )
    }
}

nonisolated extension BodyPartData {
    /// The parts whose BPND names this body-part type.
    func parts(ofType type: UInt8) -> [BodyPart] {
        parts.filter { $0.nodeData?.partType == type }
    }
}
