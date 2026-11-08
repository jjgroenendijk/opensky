// The cell stage of a preview: the target's cell, or the host cell a record stands
// in, built as the game builds it, with distant LOD around an exterior cell.

import Foundation
import OpenSkyCells
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyRendering
import OpenSkyTerrain
import simd

/// The cell a cell-stage preview builds.
nonisolated enum PreviewCellPlace: Equatable {
    /// `entryDoor` leads into the cell; the camera stands where it puts the player.
    case interior(FormID, entryDoor: FormID?)
    case exterior(worldspace: String, grid: CellCoordinate)
}

nonisolated extension PreviewSceneBuilder {
    func inCell(_ request: PreviewRequest) throws(PreviewError) -> PreviewScene {
        let place = try cellPlace(for: request)
        let (cell, cellRender) = try buildCell(place)
        var failures: [String] = []
        var extra: [RenderScene] = []
        var focus: ModelBounds?
        var entry: PlacedReference.Placement?
        var target: PreviewResolvedTarget
        switch request.target {
        case .record, .mesh:
            let spot = try request.focus.map { name throws(PreviewError) in
                try focusPlacement(name, in: cell)
            } ?? builder.previewSpot(in: cell)
            let (subject, resolved) = try studioSubject(request.target, at: spot)
            guard !subject.placements.isEmpty else {
                throw .nothingToDraw(Self.name(of: request.target), reasons: subject.failures)
            }
            extra = [RenderScene(
                instances: subject.placements, animations: subject.animations,
                pointLights: subject.pointLights
            )]
            (focus, target, failures) = (subject.bounds, resolved, subject.failures)
        case let .reference(name):
            let record = try record(named: name)
            let subject = builder.previewSubject(of: record.formID, in: cell)
            target = Self.resolved(record, kind: "reference", model: subject?.modelPath)
            focus = subject?.bounds
            failures = subject?.failures ?? ["reference \(name) is not placed in its cell"]
        case .interiorCell, .exteriorCell:
            target = PreviewResolvedTarget(kind: "cell")
            if let name = request.focus {
                let reference = try record(named: name).formID
                focus = builder.previewSubject(of: reference, in: cell)?.bounds
            } else if case let .interior(_, door?) = place {
                entry = builder.previewEntryEye(door: door)
            }
        }
        target.cell = cellName(place)
        guard let bounds = focus ?? cell.bounds.map({ ModelBounds(min: $0.min, max: $0.max) })
        else { throw .nothingToDraw(target.cell ?? "cell", reasons: failures) }
        let worldspace: String? = if case let .exterior(name, _) = place {
            name
        } else {
            nil
        }
        return PreviewScene(
            renderScene: RenderScene(merging: [cellRender] + extra), focus: bounds,
            target: target, failures: failures, stage: .cell, weatherWorldspace: worldspace,
            entry: entry
        )
    }

    private func cellPlace(for request: PreviewRequest) throws(PreviewError) -> PreviewCellPlace {
        switch request.target {
        case let .reference(name):
            let reference = try record(named: name).formID
            guard let entry = builder.previewCell(holding: reference) else {
                throw .referenceNotPlaced(name)
            }
            return Self.place(entry)
        case .interiorCell, .exteriorCell:
            return try cellPlace(of: request.target)
        case .record, .mesh:
            guard let host = request.hostCell else { throw .cellStageNeedsCell }
            return try cellPlace(of: host)
        }
    }

    private func cellPlace(of target: PreviewTarget) throws(PreviewError) -> PreviewCellPlace {
        switch target {
        case let .exteriorCell(worldspace, grid):
            return .exterior(worldspace: worldspace, grid: grid)
        case let .interiorCell(name):
            guard let entry = CellDirectory.find(editorID: name, in: builder.pluginLoadOrder)
            else { throw .notFound(name) }
            return Self.place(entry)
        case .record, .reference, .mesh:
            throw .hostIsNotACell
        }
    }

    private static func place(_ entry: CellDirectoryEntry) -> PreviewCellPlace {
        switch entry {
        case let .interior(cell, door):
            .interior(cell, entryDoor: door)
        case let .exterior(_, worldspace, grid):
            .exterior(worldspace: worldspace, grid: grid)
        }
    }

    /// The cell, and its render scene with distant LOD around an exterior cell.
    private func buildCell(
        _ place: PreviewCellPlace
    ) throws(PreviewError) -> (CellScene, RenderScene) {
        do {
            switch place {
            case let .interior(cell, _):
                let scene = try builder.buildInteriorScene(cellFormID: cell)
                return (scene, scene.renderScene)
            case let .exterior(worldspace, grid):
                let scene = try builder.buildScene(
                    worldspaceEditorID: worldspace, gridX: grid.x, gridY: grid.y
                )
                let lod = try builder.buildDistantLOD(
                    worldspaceEditorID: worldspace, center: grid, hiddenCells: [grid]
                )
                let render = lod.map { RenderScene(merging: [scene.renderScene, $0.renderScene]) }
                return (scene, render ?? scene.renderScene)
            }
        } catch {
            throw .cellFailed(String(describing: error))
        }
    }

    private func focusPlacement(
        _ name: String, in cell: CellScene
    ) throws(PreviewError) -> PlacedReference.Placement {
        let reference = try record(named: name).formID
        guard let placement = builder.previewPlacement(of: reference, in: cell) else {
            throw .referenceNotPlaced(name)
        }
        return placement
    }

    private func cellName(_ place: PreviewCellPlace) -> String {
        switch place {
        case let .interior(cell, _):
            let record = builder.pluginLoadOrder.record(withFormID: cell)
            return record.flatMap { ESMWalk.editorID(of: $0.record) } ?? cell.description
        case let .exterior(worldspace, grid):
            return "\(worldspace) (\(grid.x),\(grid.y))"
        }
    }
}
