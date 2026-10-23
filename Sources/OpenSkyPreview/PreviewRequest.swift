// What a preview renders: one target, a stage, and the camera views. The CLI builds
// this value. Pure values.
// Pipeline: docs/tools/preview-render.md.

import Foundation
import OpenSkyFormatsCore
import simd

nonisolated public enum PreviewTarget: Equatable, Sendable {
    /// A base record, by FormID token or editor ID.
    case record(String)
    /// A placed REFR or ACHR, by FormID token or editor ID.
    case reference(String)
    case interiorCell(String)
    case exteriorCell(worldspace: String, grid: CellCoordinate)
    /// A path under `meshes\`, read through the engine file system.
    case mesh(String)

    var isCell: Bool {
        switch self {
        case .interiorCell, .exteriorCell: true
        case .record, .reference, .mesh: false
        }
    }
}

nonisolated public enum PreviewStage: String, CaseIterable, Sendable {
    /// Even light on an empty background, so only the asset is checked.
    case studio
    /// The cell's own lighting, weather, and time of day.
    case cell
}

/// One camera view around the framed center.
nonisolated public struct PreviewView: Equatable, Sendable {
    public var name: String
    /// Degrees clockwise from the target's front (+Y), seen from above.
    public var yaw: Float
    /// Degrees above the horizon.
    public var pitch: Float
    /// Game units from the framed center; nil fits the bounds.
    public var distance: Float?

    public init(name: String, yaw: Float, pitch: Float, distance: Float? = nil) {
        self.name = name
        self.yaw = yaw
        self.pitch = pitch
        self.distance = distance
    }

    /// From the framed center toward the eye. Skyrim is Z-up, and an actor with no
    /// rotation faces +Y.
    public var eyeDirection: SIMD3<Float> {
        let yawRadians = yaw * .pi / 180
        let pitchRadians = min(max(pitch, -89), 89) * .pi / 180
        return SIMD3(
            sinf(yawRadians) * cosf(pitchRadians),
            cosf(yawRadians) * cosf(pitchRadians),
            sinf(pitchRadians)
        )
    }
}

nonisolated public enum PreviewAngle: String, CaseIterable, Sendable {
    case front
    case side
    case back
    case top
    case threeQuarter = "three-quarter"

    public var view: PreviewView {
        switch self {
        case .front: PreviewView(name: rawValue, yaw: 0, pitch: 10)
        case .side: PreviewView(name: rawValue, yaw: 90, pitch: 10)
        case .back: PreviewView(name: rawValue, yaw: 180, pitch: 10)
        case .top: PreviewView(name: rawValue, yaw: 0, pitch: 89)
        case .threeQuarter: PreviewView(name: rawValue, yaw: 45, pitch: 20)
        }
    }

    /// `all`, or angle names joined by commas.
    public static func views(named list: String) throws(PreviewError) -> [PreviewView] {
        if list == "all" {
            return allCases.map(\.view)
        }
        return try list.split(separator: ",").map { name throws(PreviewError) in
            guard let angle = PreviewAngle(rawValue: String(name)) else {
                throw .unknownAngle(String(name))
            }
            return angle.view
        }
    }
}

nonisolated public struct PreviewRequest: Equatable, Sendable {
    public var target: PreviewTarget
    /// Nil picks the cell stage for a cell and the studio for anything else.
    public var stage: PreviewStage?
    /// The cell a base record or a mesh stands in on the cell stage.
    public var hostCell: PreviewTarget?
    /// A reference in the cell: the camera frames it, and a base record stands there.
    public var focus: String?
    public var views: [PreviewView]
    public var timeOfDay: Float
    public var weather: String?
    public var width: Int
    public var height: Int

    public init(
        target: PreviewTarget,
        stage: PreviewStage? = nil,
        hostCell: PreviewTarget? = nil,
        focus: String? = nil,
        views: [PreviewView] = [PreviewAngle.threeQuarter.view],
        timeOfDay: Float = 13,
        weather: String? = nil,
        size: (width: Int, height: Int) = (1280, 720)
    ) {
        self.target = target
        self.stage = stage
        self.hostCell = hostCell
        self.focus = focus
        self.views = views
        self.timeOfDay = timeOfDay
        self.weather = weather
        width = size.width
        height = size.height
    }

    public var resolvedStage: PreviewStage {
        stage ?? (target.isCell ? .cell : .studio)
    }

    /// The cell stage builds the target's own cell, or the host cell for a record
    /// or a mesh. A reference finds its own cell, so it needs no host.
    public func validated() throws(PreviewError) -> Self {
        guard !views.isEmpty else { throw .noViews }
        if let hostCell, !hostCell.isCell {
            throw .hostIsNotACell
        }
        if target.isCell, stage == .studio {
            throw .cellNeedsCellStage
        }
        guard resolvedStage == .cell else { return self }
        switch target {
        case .record, .mesh:
            guard hostCell != nil else { throw .cellStageNeedsCell }
        case .reference, .interiorCell, .exteriorCell:
            break
        }
        return self
    }
}

nonisolated public enum PreviewError: Error, Equatable, CustomStringConvertible {
    case noViews
    case oneTarget
    case badGrid
    case unknownStage(String)
    case unknownAngle(String)
    case hostIsNotACell
    case cellStageNeedsCell
    case cellNeedsCellStage
    case notFound(String)
    case unsupportedRecord(type: String, name: String)
    case referenceNotPlaced(String)
    case cellFailed(String)
    case nothingToDraw(String, reasons: [String])
    case nothingDrew(view: String)

    public var description: String {
        switch self {
        case .noViews: "no camera view to render"
        case .oneTarget: "give one of record, reference, mesh, or a cell"
        case .badGrid: "a cell is an editor ID, or a worldspace with both x and y"
        case let .unknownStage(name): "unknown stage \(name); use studio or cell"
        case let .unknownAngle(name):
            "unknown angle \(name); use all, or some of: "
                + PreviewAngle.allCases.map(\.rawValue).joined(separator: ", ")
        case .hostIsNotACell: "the host must be a cell"
        case .cellStageNeedsCell: "the cell stage needs a cell for a record or a mesh"
        case .cellNeedsCellStage: "a cell renders only on the cell stage"
        case let .notFound(name): "no record, cell, or mesh named \(name)"
        case let .unsupportedRecord(type, name): "\(type) \(name) has no model to preview"
        case let .referenceNotPlaced(name): "reference \(name) is in no cell"
        case let .cellFailed(reason): "the cell did not build: \(reason)"
        case let .nothingToDraw(name, reasons):
            (["\(name) built nothing to draw"] + reasons).joined(separator: "\n  ")
        case let .nothingDrew(view): "the \(view) view drew nothing"
        }
    }
}
