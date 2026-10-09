// Any placed REFR or ACHR of the load order by key, loaded or not. `MoveTo`
// needs it for a reference whose cell is not resident, and a build needs it for
// a reference moved in from another cell. See docs/engine/reference-identity.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState
import simd

nonisolated public struct PlacedRecordLookup: Sendable {
    private let index: LoadOrderRecordIndex
    private let templates: ActorTemplateResolver?

    private var resolver: FormIDResolver {
        index.space
    }

    public init(index: LoadOrderRecordIndex, templates: ActorTemplateResolver? = nil) {
        self.index = index
        self.templates = templates
    }

    /// The winning record behind `key`, or nil for a key of a plugin outside the
    /// load order, a deleted record, or one that is not a REFR or ACHR.
    public func entry(for key: ReferenceKey) -> RuntimeReferenceEntry? {
        guard
            case let .plugin(name, objectID) = key,
            let formID = resolver.localFormID(
                of: ResolvedFormID(plugin: name, objectID: objectID)
            ),
            let found = index.record(withFormID: formID), !found.record.isDeleted
        else { return nil }
        let decoded: RuntimeReferenceRecord? = switch found.record.type {
        case "REFR": (try? found.decode(PlacedReference.init(record:))).map { .reference($0) }
        case "ACHR": (try? found.decode(PlacedActor.init(record:))).map { .actor($0) }
        default: nil
        }
        guard let decoded else { return nil }
        return RuntimeReferenceEntry(
            key: key,
            formID: formID,
            isPersistent: found.record.flags.contains(.persistent),
            record: decoded,
            baseScripts: baseScripts(of: decoded)
        )
    }

    private func baseScripts(of record: RuntimeReferenceRecord) -> [AttachedScript] {
        if case let .actor(actor) = record {
            return (try? templates?.resolveScripts(base: actor.base).value) ?? []
        }
        guard
            case let .reference(reference) = record,
            let base = index.record(withFormID: reference.base),
            ModelBase.supportedTypes.contains(base.record.type),
            let decoded = try? base.decode({ try ModelBase(record: $0, localized: base.localized) })
        else { return [] }
        return decoded.scriptData.scripts
    }

    /// The positions along the unkeyed linked references from `start`, which is the
    /// path a patrol walks. Stops at a loop, a missing link, or `limit` points.
    public func linkedChain(from start: ReferenceKey, limit: Int = 64) -> [SIMD3<Float>] {
        var points: [SIMD3<Float>] = []
        var visited: Set<ReferenceKey> = []
        var next: ReferenceKey? = start
        while
            let key = next, points.count < limit, visited.insert(key).inserted,
            let entry = entry(for: key)
        {
            if
                let position = entry.placedReference?.placement.position
                ?? entry.placedActor?.placement.position
            {
                points.append(position)
            }
            let link = entry.placedReference?.linkedReferences.first { $0.keyword == nil }
            next = link.flatMap { ReferenceKey.resolve($0.ref, using: resolver) }
        }
        return points
    }

    /// The cell that draws `entry` from its plugin position: its interior, or
    /// the exterior cell its position falls in.
    public func home(of entry: RuntimeReferenceEntry) -> CellSceneLocation? {
        if let interior = interiorCell(holding: entry.formID) {
            return .interior(interior)
        }
        let position = entry.placedReference?.placement.position
            ?? entry.placedActor?.placement.position
        return position.map { .exterior(CellGridManager.cellCoordinate(for: $0)) }
    }

    /// The interior CELL whose children hold `formID`; nil for an exterior one.
    public func interiorCell(holding formID: FormID) -> FormID? {
        guard
            let cellID = index.cellFormID(containing: formID),
            let found = index.record(withFormID: cellID), found.record.type == "CELL",
            let cell = try? Cell(record: found.record, localized: found.localized), cell.isInterior
        else { return nil }
        return cellID
    }
}
