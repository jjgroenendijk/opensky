// The JSON a preview writes beside its images: one report per view, and a summary
// that lists them. Pure values; the CLI writes the files.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct PreviewViewReport: Codable, Equatable, Sendable {
    public var view: String
    public var image: String
    public var yaw: Float
    public var pitch: Float
    public var distance: Float
    public var drawCalls: Int
    public var drawnInstances: Int
    public var triangles: Int
    /// Share of pixels that are not background, from 0 to 1.
    public var coverage: Double
    public var blank: Bool
    public var boundsMin: [Float]
    public var boundsMax: [Float]
    public var target: PreviewResolvedTarget
    public var stage: String
    public var timeOfDay: Float
    public var weather: String?
    /// Every mesh, texture, or record that did not resolve.
    public var failures: [String]
}

nonisolated public struct PreviewReport: Codable, Equatable, Sendable {
    public var target: PreviewResolvedTarget
    public var stage: String
    public var views: [PreviewViewReport]

    /// Fails when any view is blank.
    public var passed: Bool {
        !views.isEmpty && views.allSatisfy { !$0.blank }
    }

    public init(target: PreviewResolvedTarget, stage: String, views: [PreviewViewReport]) {
        self.target = target
        self.stage = stage
        self.views = views
    }

    public func json() throws -> Data {
        try Self.encoder.encode(self)
    }

    public static func json(_ view: PreviewViewReport) throws -> Data {
        try encoder.encode(view)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

/// The measures of one rendered view, without the texture, so a report can be built
/// and tested off the GPU.
nonisolated public struct PreviewViewMeasure: Equatable, Sendable {
    public var view: PreviewView
    public var distance: Float
    public var drawCalls: Int
    public var drawnInstances: Int
    public var triangles: Int
    public var coverage: Double

    public init(
        view: PreviewView, distance: Float, drawCalls: Int, drawnInstances: Int,
        triangles: Int, coverage: Double
    ) {
        self.view = view
        self.distance = distance
        self.drawCalls = drawCalls
        self.drawnInstances = drawnInstances
        self.triangles = triangles
        self.coverage = coverage
    }

    public var isBlank: Bool {
        drawnInstances == 0 || coverage == 0
    }
}

nonisolated extension PreviewReport {
    /// `image` names each view's PNG, such as `front.png`.
    public init(
        target: PreviewResolvedTarget,
        stage: PreviewStage,
        request: PreviewRequest,
        focus: ModelBounds,
        failures: [String],
        measures: [PreviewViewMeasure]
    ) {
        let views = measures.map { measure in
            PreviewViewReport(
                view: measure.view.name,
                image: "\(measure.view.name).png",
                yaw: measure.view.yaw,
                pitch: measure.view.pitch,
                distance: measure.distance,
                drawCalls: measure.drawCalls,
                drawnInstances: measure.drawnInstances,
                triangles: measure.triangles,
                coverage: measure.coverage,
                blank: measure.isBlank,
                boundsMin: [focus.min.x, focus.min.y, focus.min.z],
                boundsMax: [focus.max.x, focus.max.y, focus.max.z],
                target: target,
                stage: stage.rawValue,
                timeOfDay: request.timeOfDay,
                weather: request.weather,
                failures: failures
            )
        }
        self.init(target: target, stage: stage.rawValue, views: views)
    }
}
