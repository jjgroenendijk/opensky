// `interior`: repeatable real-install acceptance probe for M3.6. Finds an
// exterior teleport door near the requested cell, follows XTEL into an
// interior, renders the exact arrival pose, then follows the paired door back.

import Foundation
import Metal
import MetalKit
import simd

enum InteriorCommand {
    private struct Candidate {
        let source: PlacedDoor
        let transition: DoorTransition
    }

    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let worldspace = try scanner.option("--worldspace")
            ?? FirstRenderCell.worldspaceEditorID
        let gridX = try RenderCommand.int32(scanner.option("--x"), name: "--x")
            ?? FirstRenderCell.gridX
        let gridY = try RenderCommand.int32(scanner.option("--y"), name: "--y")
            ?? FirstRenderCell.gridY
        let radius = try parseRadius(scanner.option("--radius"))
        let output = try scanner.requiredOption("--out")
        try scanner.finish()

        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal4)
        else {
            throw CLIError.failure("no Metal 4 GPU available")
        }

        let builder = try RenderCommand.makeBuilder(context: context, device: device)
        let center = CellCoordinate(x: gridX, y: gridY)
        guard
            let candidate = findCandidate(
                builder: builder,
                worldspace: worldspace,
                center: center,
                radius: radius
            )
        else {
            throw CLIError.failure("no exterior-to-interior door found within radius \(radius)")
        }

        let transition = candidate.transition
        guard case let .interior(interiorID)? = transition.scene.location else {
            throw CLIError.failure("selected destination is not an interior cell")
        }
        let reverse = try builder.buildDoorTransition(
            from: transition.destinationDoor,
            worldspaceEditorID: worldspace
        )
        guard case let .exterior(exteriorCoordinate)? = reverse.scene.location else {
            throw CLIError.failure("destination door does not return to an exterior cell")
        }
        guard reverse.destinationDoor == candidate.source.reference else {
            throw CLIError.failure("return door does not target the source door")
        }

        let render = try RenderCommand.renderOffscreen(
            device: device,
            scene: transition.scene.renderScene,
            camera: .teleport(placement: transition.destinationPlacement),
            size: (1280, 720),
            timeOfDay: 13
        )
        let outputURL = URL(filePath: output)
        try FrameScreenshot.write(texture: render.texture, to: outputURL)

        print("[INFO] source door \(transition.sourceDoor) at \(candidate.source.position)")
        print("[INFO] entered \(describe(.interior(interiorID))) via "
            + "\(transition.destinationDoor)")
        print(transition.scene.summary.summaryLine)
        print("[INFO] returned to \(describe(.exterior(exteriorCoordinate))) via "
            + "\(reverse.destinationDoor)")
        print("[INFO] wrote interior frame -> \(outputURL.path(percentEncoded: false))")
    }

    private static func findCandidate(
        builder: CellSceneBuilder,
        worldspace: String,
        center: CellCoordinate,
        radius: Int32
    ) -> Candidate? {
        guard let allDoors = try? builder.exteriorDoors(worldspaceEditorID: worldspace)
        else { return nil }
        let doors = allDoors.filter {
            abs($0.coordinate.x - center.x) <= radius
                && abs($0.coordinate.y - center.y) <= radius
        }.sorted {
            simd_distance_squared($0.door.position, CellGridManager.cellCenter(of: center))
                < simd_distance_squared($1.door.position, CellGridManager.cellCenter(of: center))
        }
        for entry in doors {
            guard
                let transition = try? builder.buildDoorTransition(
                    from: entry.door.reference,
                    worldspaceEditorID: worldspace
                ),
                case .interior = transition.scene.location
            else { continue }
            return Candidate(source: entry.door, transition: transition)
        }
        return nil
    }

    private static func parseRadius(_ value: String?) throws -> Int32 {
        guard let value else { return 16 }
        guard let radius = Int32(value), (0 ... 64).contains(radius) else {
            throw CLIError.usage("--radius expects an integer in 0-64, got \(value)")
        }
        return radius
    }

    private static func describe(_ location: CellSceneLocation) -> String {
        switch location {
        case let .exterior(coordinate):
            "exterior cell (\(coordinate.x),\(coordinate.y))"
        case let .interior(formID):
            "interior cell \(formID)"
        }
    }
}
