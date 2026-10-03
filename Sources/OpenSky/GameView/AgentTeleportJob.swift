// One `debug.teleport` from request to settled player. It finds the cell, moves
// the camera or walks through a door, waits for the cells to load, then lets
// two frames pass so the reply reports where the player really stands.

import Foundation
import OpenSkyAgentControl
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRendering
import OpenSkyWorld
import OpenSkyWorldState
import simd

@MainActor
final class AgentTeleportJob {
    private enum Phase {
        case lookingUp
        case loadingGrid(CellCoordinate)
        case loadingInterior(FormID)
        case settling(untilFrame: Int)
    }

    static let timeoutSeconds = 120.0
    static let settleFrames = 2

    private unowned let adapter: AgentWorldAdapter
    private var phase: Phase
    private var deadline: Double?
    private var lookup: Result<CellDirectoryEntry?, AgentFailure>?

    private var game: GameViewController {
        adapter.game
    }

    init(adapter: AgentWorldAdapter, target: AgentTeleportTarget) throws(AgentFailure) {
        self.adapter = adapter
        guard let renderer = adapter.game.renderer, let streamer = adapter.game.streamer else {
            throw adapter.notReady()
        }
        guard streamer.transitionInFlight == nil else {
            throw AgentFailure(.notReady, "a door transition is still loading")
        }
        switch target {
        case let .position(position):
            phase = .settling(untilFrame: 0)
            place(at: position, renderer: renderer, streamer: streamer, leavingInterior: false)
            phase = settling()
        case let .reference(text):
            let reference = try adapter.resolveReference(text)
            guard
                let placement = streamer.referenceEntry(key: reference.key)?.placedReference?
                    .placement
            else {
                throw AgentFailure(.notFound, "the reference has no placement")
            }
            phase = .settling(untilFrame: 0)
            place(
                at: placement.position,
                renderer: renderer,
                streamer: streamer,
                leavingInterior: false
            )
            phase = settling()
        case let .grid(x, y):
            phase = .lookingUp
            enterGrid(CellCoordinate(x: x, y: y))
        case let .cell(editorID):
            phase = .lookingUp
            try startLookup(editorID)
        }
    }

    var wait: AgentWait {
        AgentWait { [self] now in poll(now) }
    }

    private func poll(_ now: Double) -> AgentWaitStep {
        let limit = deadline ?? now + Self.timeoutSeconds
        deadline = limit
        if now > limit {
            return .done(.failure(AgentFailure(
                .timeout,
                "the teleport did not finish in \(Int(Self.timeoutSeconds)) s"
            )))
        }
        do throws(AgentFailure) {
            return try advance()
        } catch {
            return .done(.failure(error))
        }
    }

    private func advance() throws(AgentFailure) -> AgentWaitStep {
        guard let streamer = game.streamer else { throw adapter.notReady() }
        switch phase {
        case .lookingUp:
            try finishLookup()
        case let .loadingGrid(grid):
            guard
                streamer.composition.cells[grid] != nil,
                adapter.isWorldReady else { return .wait }
            snapToGround(in: grid)
            phase = settling()
        case let .loadingInterior(cell):
            guard
                streamer.transitionInFlight == nil,
                streamer.interiorScene?.location == .interior(cell)
            else { return .wait }
            phase = settling()
        case let .settling(untilFrame):
            guard
                adapter.isWorldReady,
                game.simulationClock.frame >= untilFrame else { return .wait }
            return try .done(.success(adapter.query(.player)))
        }
        return .wait
    }

    private func settling() -> Phase {
        .settling(untilFrame: game.simulationClock.frame + Self.settleFrames)
    }

    // MARK: - Cells by editor ID

    private func startLookup(_ editorID: String) throws(AgentFailure) {
        guard let root = adapter.dataRoot else {
            throw AgentFailure(.notReady, "no game data is loaded")
        }
        let url = root.dataURL.appending(path: "Skyrim.esm")
        Task { [weak self] in
            let result = await Self.findCell(editorID, in: url)
            self?.lookup = result
        }
    }

    private func finishLookup() throws(AgentFailure) {
        guard let lookup else { return }
        guard let entry = try lookup.get() else {
            throw AgentFailure(.notFound, "no cell with that editor ID in Skyrim.esm")
        }
        switch entry {
        case let .exterior(_, grid):
            enterGrid(grid)
        case let .interior(cell, entryDoor):
            guard let entryDoor else {
                throw AgentFailure(.unsupported, "the interior has no door to enter through")
            }
            guard game.streamer?.requestDoorTransition(from: entryDoor) == true else {
                throw AgentFailure(.notReady, "a door transition is still loading")
            }
            phase = .loadingInterior(cell)
        }
    }

    @concurrent
    nonisolated private static func findCell(
        _ editorID: String,
        in url: URL
    ) async -> Result<CellDirectoryEntry?, AgentFailure> {
        do {
            let file = try ESMFile(url: url)
            return .success(CellDirectory.find(editorID: editorID, in: file))
        } catch {
            return .failure(AgentFailure(.failed, "could not read Skyrim.esm: \(error)"))
        }
    }

    // MARK: - Moving the player

    private func enterGrid(_ grid: CellCoordinate) {
        guard let renderer = game.renderer, let streamer = game.streamer else { return }
        let center = Self.center(of: grid)
        // The height is a guess until the cell's terrain loads; then the
        // player is put on the ground.
        let height = streamer.sampleTerrain(at: center)?.height ?? 0
        place(at: SIMD3(center, height), renderer: renderer, streamer: streamer)
        phase = .loadingGrid(grid)
    }

    private func snapToGround(in grid: CellCoordinate) {
        guard let renderer = game.renderer, let streamer = game.streamer else { return }
        let center = Self.center(of: grid)
        guard let ground = streamer.sampleTerrain(at: center) else { return }
        place(at: SIMD3(center, ground.height), renderer: renderer, streamer: streamer)
    }

    /// A position or a reference stays in the current cell, because interior
    /// coordinates are local to their cell. A grid teleport leaves the interior.
    private func place(
        at feet: SIMD3<Float>,
        renderer: Renderer,
        streamer: CellStreamer,
        leavingInterior: Bool = true
    ) {
        let rotation = SIMD3<Float>(0, 0, renderer.freeFlyCamera.yaw)
        let camera = SceneCamera.teleport(placement: .init(position: feet, rotation: rotation))
        if leavingInterior, streamer.interiorScene != nil {
            streamer.leaveInterior(camera: camera)
        } else {
            renderer.camera = camera
            renderer.reseedMovement(camera: camera)
        }
    }

    private static func center(of grid: CellCoordinate) -> SIMD2<Float> {
        SIMD2(
            (Float(grid.x) + 0.5) * CellCoordinate.cellSize,
            (Float(grid.y) + 0.5) * CellCoordinate.cellSize
        )
    }
}
