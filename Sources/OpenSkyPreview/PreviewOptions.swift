// The options of a preview as a person gives them, on the command line or in the
// sidebar, and the one rule that turns them into a `PreviewRequest`.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct PreviewOptions: Equatable, Sendable {
    public var record: String?
    public var reference: String?
    public var mesh: String?
    public var cell: String?
    public var worldspace: String?
    public var x: Int32?
    public var y: Int32?
    public var stage: String?
    public var focus: String?
    public var angles: String?
    public var yaw: Float?
    public var pitch: Float?
    public var distance: Float?
    public var timeOfDay: Float = 13
    public var weather: String?
    public var width = 1280
    public var height = 720

    public init() {}

    /// One of record, reference, or mesh is the target, and a cell option then names
    /// the cell it stands in. Without one of them, the cell is the target.
    public func request() throws(PreviewError) -> PreviewRequest {
        let subjects: [PreviewTarget] = [
            record.map(PreviewTarget.record), reference.map(PreviewTarget.reference),
            mesh.map(PreviewTarget.mesh)
        ].compactMap(\.self)
        let place = try cellTarget()
        guard subjects.count <= 1, let target = subjects.first ?? place else {
            throw .oneTarget
        }
        let host = subjects.isEmpty ? nil : place
        var stage = try stage.map { name throws(PreviewError) in
            guard let stage = PreviewStage(rawValue: name) else { throw .unknownStage(name) }
            return stage
        }
        if stage == nil, host != nil {
            stage = .cell
        }
        return try PreviewRequest(
            target: target, stage: stage, hostCell: host, focus: focus, views: views(),
            timeOfDay: timeOfDay, weather: weather, size: (width, height)
        ).validated()
    }

    private func cellTarget() throws(PreviewError) -> PreviewTarget? {
        switch (cell, x, y) {
        case (nil, nil, nil):
            guard worldspace == nil else { throw .badGrid }
            return nil
        case let (name?, nil, nil):
            guard worldspace == nil else { throw .badGrid }
            return .interiorCell(name)
        case let (nil, x?, y?):
            return .exteriorCell(
                worldspace: worldspace ?? "Tamriel", grid: CellCoordinate(x: x, y: y)
            )
        default:
            throw .badGrid
        }
    }

    /// The named angles, or one view from yaw and pitch; `distance` applies to each.
    private func views() throws(PreviewError) -> [PreviewView] {
        var views: [PreviewView] = if let angles {
            try PreviewAngle.views(named: angles)
        } else if yaw != nil || pitch != nil {
            [PreviewView(name: "custom", yaw: yaw ?? 45, pitch: pitch ?? 20)]
        } else {
            [PreviewAngle.threeQuarter.view]
        }
        for index in views.indices {
            views[index].distance = distance
        }
        return views
    }
}

/// The kinds of target the sidebar offers, in its menu order.
nonisolated public enum PreviewTargetKind: String, CaseIterable, Sendable {
    case record
    case reference
    case mesh
    case cell

    public var title: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }
}

nonisolated extension PreviewOptions {
    /// The sidebar's fields: one target text of `kind`, and an optional cell text
    /// that names the cell a record, reference, or mesh stands in.
    public init(kind: PreviewTargetKind, target: String, inCell: String) throws(PreviewError) {
        self.init()
        let target = target.trimmingCharacters(in: .whitespaces)
        switch kind {
        case .record: record = target.isEmpty ? nil : target
        case .reference: reference = target.isEmpty ? nil : target
        case .mesh: mesh = target.isEmpty ? nil : target
        case .cell: try setCell(target)
        }
        if kind != .cell {
            try setCell(inCell)
        }
    }

    /// An editor ID, or a worldspace and a grid: `Tamriel 8 25`.
    public mutating func setCell(_ text: String) throws(PreviewError) {
        let words = text.split(separator: " ").map(String.init)
        switch words.count {
        case 0:
            return
        case 1:
            cell = words[0]
        case 3:
            guard let x = Int32(words[1]), let y = Int32(words[2]) else { throw .badGrid }
            (worldspace, self.x, self.y) = (words[0], x, y)
        default:
            throw .badGrid
        }
    }
}
