// Turns a `PreviewRequest` into one render scene and the box the camera frames. Runs
// off the main actor, because it reads plugins and meshes.
// Pipeline: docs/tools/preview-render.md.

import Foundation
import OpenSkyCells
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyRenderCore
import OpenSkyRendering
import simd

/// What the target resolved to, for the report.
nonisolated public struct PreviewResolvedTarget: Codable, Equatable, Sendable {
    public var kind: String
    public var recordType: String?
    public var editorID: String?
    public var formID: String?
    public var plugin: String?
    public var modelPath: String?
    public var cell: String?

    public init(kind: String) {
        self.kind = kind
    }
}

nonisolated public struct PreviewScene: Sendable {
    public var renderScene: RenderScene
    /// The box the camera frames.
    public var focus: ModelBounds
    public var target: PreviewResolvedTarget
    public var failures: [String]
    public var stage: PreviewStage
    /// The worldspace whose weather the cell stage shows; nil indoors and in the studio.
    public var weatherWorldspace: String?
    /// The eye of a player entering an interior; views then turn from there.
    public var entry: PlacedReference.Placement?
}

nonisolated public struct PreviewSceneBuilder {
    public let builder: CellSceneBuilder

    public init(builder: CellSceneBuilder) {
        self.builder = builder
    }

    private var loadOrder: LoadOrderPlugins {
        builder.pluginLoadOrder
    }

    public func build(_ request: PreviewRequest) throws(PreviewError) -> PreviewScene {
        let request = try request.validated()
        switch request.resolvedStage {
        case .studio:
            return try studio(request)
        case .cell:
            return try inCell(request)
        }
    }

    // MARK: - Studio

    private func studio(_ request: PreviewRequest) throws(PreviewError) -> PreviewScene {
        let origin = PlacedReference.Placement(position: .zero, rotation: .zero)
        let (subject, target) = try studioSubject(request.target, at: origin)
        guard let focus = subject.bounds, !subject.placements.isEmpty else {
            throw .nothingToDraw(Self.name(of: request.target), reasons: subject.failures)
        }
        let scene = RenderScene(
            instances: subject.placements,
            animations: subject.animations,
            lighting: PreviewStudio.lighting,
            pointLights: subject.pointLights
        )
        return PreviewScene(
            renderScene: scene, focus: focus, target: target, failures: subject.failures,
            stage: .studio, weatherWorldspace: nil, entry: nil
        )
    }

    func studioSubject(
        _ target: PreviewTarget, at origin: PlacedReference.Placement
    ) throws(PreviewError) -> (PreviewSubject, PreviewResolvedTarget) {
        switch target {
        case let .mesh(path):
            let subject = builder.previewMesh(path: path, placement: origin)
            var resolved = PreviewResolvedTarget(kind: "mesh")
            resolved.modelPath = path
            return (subject, resolved)
        case let .record(name):
            let record = try record(named: name)
            let subject = try baseSubject(record, placement: origin)
            return (subject, Self.resolved(record, kind: "record", model: subject.modelPath))
        case let .reference(name):
            let record = try record(named: name)
            let placed = try placement(of: record, name: name)
            let base = try self.record(formID: placed.base, name: name)
            let spot = PlacedReference.Placement(
                position: .zero, rotation: placed.placement.rotation
            )
            let subject = try baseSubject(base, placement: spot, scale: placed.scale)
            return (subject, Self.resolved(record, kind: "reference", model: subject.modelPath))
        case .interiorCell, .exteriorCell:
            throw .cellNeedsCellStage
        }
    }

    // MARK: - Records

    func record(named name: String) throws(PreviewError) -> LoadOrderRecord {
        guard let record = loadOrder.record(named: name) else { throw .notFound(name) }
        return record
    }

    private func record(formID: FormID, name: String) throws(PreviewError) -> LoadOrderRecord {
        guard let record = loadOrder.record(withFormID: formID) else {
            throw .notFound("\(name) base \(formID)")
        }
        return record
    }

    /// The base, spot, and scale of a REFR or ACHR record.
    private func placement(
        of record: LoadOrderRecord, name: String
    ) throws(PreviewError) -> PreviewPlacedBase {
        do {
            switch record.record.type {
            case "REFR":
                let placed = try record.decode { try PlacedReference(record: $0) }
                return PreviewPlacedBase(
                    base: placed.base, placement: placed.placement, scale: placed.scale
                )
            case "ACHR":
                let placed = try record.decode { try PlacedActor(record: $0) }
                return PreviewPlacedBase(
                    base: placed.base, placement: placed.placement, scale: placed.scale
                )
            default:
                throw PreviewError.unsupportedRecord(
                    type: record.record.type.description,
                    name: name
                )
            }
        } catch let error as PreviewError {
            throw error
        } catch {
            throw .notFound("\(name): \(String(describing: error))")
        }
    }

    /// An NPC_ is assembled; ARMO shows its ground model; anything else draws its model.
    func baseSubject(
        _ record: LoadOrderRecord, placement: PlacedReference.Placement, scale: Float = 1
    ) throws(PreviewError) -> PreviewSubject {
        let type = record.record.type
        let name = ESMWalk.editorID(of: record.record) ?? record.formID.description
        switch type {
        case "NPC_":
            return builder.previewActor(base: record.formID, placement: placement)
        case "ARMO":
            let armor = try? record.decode { try Armor(record: $0, localized: record.localized) }
            let model = armor?.details.maleWorldModel ?? armor?.details.femaleWorldModel
            guard let path = model?.path else {
                throw .unsupportedRecord(type: type.description, name: name)
            }
            return builder.previewMesh(path: path, placement: placement, scale: scale)
        default:
            guard
                let subject = builder.previewObject(
                    base: record.formID, placement: placement, scale: scale
                )
            else { throw .unsupportedRecord(type: type.description, name: name) }
            return subject
        }
    }

    static func resolved(
        _ record: LoadOrderRecord, kind: String, model: String?
    ) -> PreviewResolvedTarget {
        var resolved = PreviewResolvedTarget(kind: kind)
        resolved.recordType = record.record.type.description
        resolved.editorID = ESMWalk.editorID(of: record.record)
        resolved.formID = record.formID.description
        resolved.plugin = record.plugin.name
        resolved.modelPath = model
        return resolved
    }

    static func name(of target: PreviewTarget) -> String {
        switch target {
        case let .record(name), let .reference(name), let .interiorCell(name), let .mesh(name):
            name
        case let .exteriorCell(worldspace, grid):
            "\(worldspace) (\(grid.x),\(grid.y))"
        }
    }
}

/// The studio stage: even light from above the front, no sky, no fog.
nonisolated public enum PreviewStudio {
    public static let lighting = RenderLighting(
        ambientColor: SIMD3(repeating: 0.55),
        directionalAmbient: DirectionalAmbientColors(
            positiveX: SIMD3(repeating: 0.5), negativeX: SIMD3(repeating: 0.5),
            positiveY: SIMD3(repeating: 0.55), negativeY: SIMD3(repeating: 0.45),
            positiveZ: SIMD3(repeating: 0.6), negativeZ: SIMD3(repeating: 0.3)
        ),
        directionalDirection: simd_normalize(SIMD3(0.3, -0.5, -1)),
        directionalColor: SIMD3(repeating: 0.9),
        fog: nil
    )

    /// The clear colour behind the subject: a mid grey, so dark and light assets
    /// both stand out.
    public static let background = SIMD3<Double>(0.18, 0.18, 0.2)
}

/// What a placed reference draws, where, and at which scale.
nonisolated struct PreviewPlacedBase {
    let base: FormID
    let placement: PlacedReference.Placement
    let scale: Float
}
