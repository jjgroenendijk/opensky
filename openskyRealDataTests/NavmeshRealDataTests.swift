// Env-gated NAVM census over the user's own Skyrim SE install (read-only
// external input, never committed — AGENTS.md Legal & IP): decodes every
// navmesh in the milestone target area — the Whiterun interior cells, the
// WhiterunWorld city exteriors, and the Tamriel exteriors around the
// first-render cell — and reports totals. Acceptance gate for issue #199: the
// whole set decodes with zero unexplained failures, and every NVNM's own
// parent matches the CELL it was found under, which is the check that settles
// xEdit's parent rule against UESP's. Skips automatically when
// OPENSKY_DATA_ROOT is unset/unresolvable (CI has no game data). Summary
// printed + written to logs/.

import Foundation
@testable import opensky
import Testing

struct NavmeshRealDataTests {
    /// Real data only when explicitly pointed at via the env var; the
    /// locator's Steam-default fallback is deliberately not consulted so
    /// machines without the override skip deterministically.
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    /// Tamriel exteriors around the first-render cell, and the whole of the
    /// WhiterunWorld city worldspace, whose populated span is small.
    private static let targetWorlds: [(editorID: String, span: Int32)] = [
        ("Tamriel", 3), ("WhiterunWorld", 12)
    ]
    /// Interior cells whose editor ID starts with this belong to the hold's
    /// interiors — the Bannered Mare, Dragonsreach, the houses, the barracks.
    private static let interiorPrefix = "Whiterun"

    @Test(.enabled(if: Self.dataRoot != nil))
    func decodesEveryWhiterunAreaNavmesh() throws {
        let root = try #require(Self.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let localized = (try? file.pluginHeader().isLocalized) ?? false
        let index = NavmeshIndex(file: file)
        #expect(!index.isEmpty, "NAVI decoded no navmesh index entries")

        let cells = targetCells(in: file, localized: localized)
        #expect(!cells.isEmpty, "no target-area cells found — install layout unexpected")

        var census = NavmeshCensus()
        for cell in cells {
            accumulate(cell: cell, index: index, into: &census)
        }
        let indexCensus = try NavmeshIndexCensus(map: #require(naviMap(in: file)))
        let summary = NavmeshCensusReport.text(
            area: census, index: indexCensus, cells: cells.count
        )
        print(summary)
        try? summary.write(to: logURL, atomically: true, encoding: .utf8)

        #expect(census.records > 0, "target area decoded no navmeshes at all")
        #expect(census.failures.isEmpty, "NAVM decode failures:\n\(list(census.failures))")
        #expect(
            census.locationMismatches.isEmpty,
            "NVNM parent disagrees with the CELL it sits under:\n\(list(census.locationMismatches))"
        )
        #expect(
            census.indexLocationMismatches.isEmpty,
            "NVNM parent disagrees with its NVMI entry:\n\(list(census.indexLocationMismatches))"
        )
        #expect(
            census.missingFromIndex.isEmpty,
            "navmeshes with no NAVI entry:\n\(list(census.missingFromIndex))"
        )
        #expect(census.versions == [12], "unexpected NVNM versions: \(census.versions.sorted())")
        #expect(indexCensus.malformedInfos == 0, "malformed NVMI entries in NAVI")
        #expect(census.triangles > 0)
        #expect(census.doorLinks > 0, "no door links in an area full of doors")
    }

    /// One cell in the target area, paired with the children group its
    /// navmeshes live in.
    private struct TargetCell {
        let formID: UInt32
        let editorID: String?
        let location: NavmeshLocation
        let children: ESMGroup
    }

    private func accumulate(
        cell: TargetCell,
        index: NavmeshIndex,
        into census: inout NavmeshCensus
    ) {
        let place = cell.editorID ?? FormID(cell.formID).description
        var navmeshes: [Navmesh] = []
        for record in navmRecords(in: cell.children) {
            do {
                try navmeshes.append(Navmesh(record: record))
            } catch {
                census.failures.append("\(place) \(FormID(record.formID)): \(error)")
            }
        }
        for navmesh in navmeshes {
            census.accumulate(navmesh)
            let name = "\(navmesh.formID) in \(cell.editorID ?? FormID(cell.formID).description)"
            if navmesh.geometry.location != cell.location {
                census.locationMismatches.append(name)
            }
            guard let info = index.info(navmesh.formID) else {
                census.missingFromIndex.append(name)
                continue
            }
            if info.location != navmesh.geometry.location {
                census.indexLocationMismatches.append(name)
            }
        }
        // The production walk logs and skips a failure rather than reporting
        // it, so the probe decodes the records itself for the error text. What
        // the walk owes is agreement: the same records, minus the failures.
        if CellSceneBuilder.collectNavmeshes(in: cell.children).count != navmeshes.count {
            census.failures.append("\(place): collectNavmeshes disagrees with a direct decode")
        }
    }

    // MARK: - Target-area walk

    /// Every cell in the target area, exterior and interior alike.
    private func targetCells(in file: ESMFile, localized: Bool) -> [TargetCell] {
        var cells: [TargetCell] = []
        for world in Self.targetWorlds {
            guard
                let identity = worldChildren(of: world.editorID, in: file, localized: localized)
            else { continue }
            var found: [TargetCell] = []
            collectExteriorCells(
                in: identity.group,
                world: identity.formID,
                span: world.span,
                localized: localized,
                into: &found
            )
            cells += found
        }
        cells += interiorCells(in: file, localized: localized)
        return cells
    }

    /// The world-children group for the WRLD whose editor ID matches, with the
    /// worldspace FormID an exterior navmesh names as its parent.
    private func worldChildren(
        of editorID: String,
        in file: ESMFile,
        localized: Bool
    ) -> (formID: UInt32, group: ESMGroup)? {
        guard let top = file.topGroup(of: "WRLD"), let children = try? top.children() else {
            return nil
        }
        var matched: UInt32?
        for child in children {
            switch child {
            case let .record(record) where record.type == "WRLD":
                let world = try? Worldspace(record: record, localized: localized)
                matched = world?.editorID == editorID ? record.formID : nil
            case let .group(group)
                where group.kind == .worldChildren && group.parentFormID == matched:
                return matched.map { ($0, group) }
            default:
                break
            }
        }
        return nil
    }

    /// Exterior CELLs within `span` squares of the first-render cell, paired
    /// with their children groups.
    private func collectExteriorCells(
        in group: ESMGroup,
        world: UInt32,
        span: Int32,
        localized: Bool,
        into cells: inout [TargetCell]
    ) {
        guard let children = try? group.children() else { return }
        for (offset, child) in children.enumerated() {
            switch child {
            case let .record(record) where record.type == "CELL":
                guard
                    let cell = try? Cell(record: record, localized: localized),
                    let grid = cell.grid,
                    abs(grid.x - FirstRenderCell.gridX) <= span,
                    abs(grid.y - FirstRenderCell.gridY) <= span,
                    let group = cellChildren(following: offset, in: children, parent: record.formID)
                else { continue }
                cells.append(TargetCell(
                    formID: record.formID,
                    editorID: cell.editorID,
                    location: .exterior(world: FormID(world), x: grid.x, y: grid.y),
                    children: group
                ))
            case let .group(sub)
                where sub.kind == .exteriorCellBlock || sub.kind == .exteriorCellSubBlock:
                collectExteriorCells(
                    in: sub, world: world, span: span, localized: localized, into: &cells
                )
            default:
                break
            }
        }
    }

    /// Interior CELLs under the CELL top group whose editor ID names the hold.
    private func interiorCells(in file: ESMFile, localized: Bool) -> [TargetCell] {
        guard let top = file.topGroup(of: "CELL") else { return [] }
        var cells: [TargetCell] = []
        collectInteriorCells(in: top, localized: localized, into: &cells)
        return cells
    }

    private func collectInteriorCells(
        in group: ESMGroup,
        localized: Bool,
        into cells: inout [TargetCell]
    ) {
        guard let children = try? group.children() else { return }
        for (offset, child) in children.enumerated() {
            switch child {
            case let .record(record) where record.type == "CELL":
                guard
                    let cell = try? Cell(record: record, localized: localized),
                    let editorID = cell.editorID,
                    editorID.hasPrefix(Self.interiorPrefix),
                    let group = cellChildren(following: offset, in: children, parent: record.formID)
                else { continue }
                cells.append(TargetCell(
                    formID: record.formID,
                    editorID: editorID,
                    location: .interior(cell: FormID(record.formID)),
                    children: group
                ))
            case let .group(sub)
                where sub.kind == .interiorCellBlock || sub.kind == .interiorCellSubBlock:
                collectInteriorCells(in: sub, localized: localized, into: &cells)
            default:
                break
            }
        }
    }

    /// The cell-children group that follows a CELL record in its block.
    private func cellChildren(
        following offset: Int,
        in children: [ESMGroup.Child],
        parent: UInt32
    ) -> ESMGroup? {
        for case let .group(group) in children[(offset + 1)...]
            where group.kind == .cellChildren && group.parentFormID == parent
        {
            return group
        }
        return nil
    }

    /// Raw undeleted NAVM records under a cell-children group, decoded or not.
    private func navmRecords(in cellChildren: ESMGroup) -> [ESMRecord] {
        guard let children = try? cellChildren.children() else { return [] }
        var found: [ESMRecord] = []
        for case let .group(group) in children {
            guard
                group.kind == .cellPersistentChildren || group.kind == .cellTemporaryChildren,
                let records = try? group.children()
            else { continue }
            for case let .record(record) in records
                where record.type == "NAVM" && !record.isDeleted
            {
                found.append(record)
            }
        }
        return found
    }

    private func naviMap(in file: ESMFile) -> NavmeshInfoMap? {
        guard let group = file.topGroup(of: "NAVI"), let children = try? group.children() else {
            return nil
        }
        for case let .record(record) in children
            where record.type == "NAVI" && !record.isDeleted
        {
            return try? NavmeshInfoMap(record: record)
        }
        return nil
    }

    private func list(_ entries: [String]) -> String {
        entries.prefix(20).joined(separator: "\n")
    }

    /// logs/navmesh-census.log (gitignored) beside the other real-data
    /// sidecars.
    private var logURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // openskyRealDataTests/
            .deletingLastPathComponent() // repo root
            .appending(path: "logs")
            .appending(path: "navmesh-census.log")
    }
}
