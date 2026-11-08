// One `debug.teleport` from request to settled player. It finds the cell, moves
// the camera or walks through a door, waits for the cells to load, then lets
// two frames pass so the reply reports where the player really stands.

import Foundation
public import OpenSkyAgentControl
public import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
public import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkySave
public import OpenSkySaveInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

@MainActor
public final class AgentTeleportJob {
    private enum Phase {
        case lookingUp
        case loadingGrid(CellCoordinate)
        case loadingInterior(FormID)
        case settling(untilFrame: Int)
    }

    public static let timeoutSeconds = 120.0
    public static let settleFrames = 2

    private unowned let adapter: AgentWorldAdapter
    private var phase: Phase
    private var deadline: Double?
    private var lookup: Result<CellDirectoryEntry?, AgentFailure>?
    private var referenceLookup: Result<ReferenceLookup?, AgentFailure>?
    /// Where a reference outside the loaded cells stands, once its cell has loaded.
    private var exactFeet: SIMD3<Float>?
    /// The `--ref` found offline, so a loaded actor is met where it stands now.
    private var lookedUpReference: String?
    /// A saved facing; other moves keep the current one.
    private var exactYaw: Float?
    /// Radians up; a move without one looks level.
    private var exactPitch: Float?
    /// The exterior worldspace to stand in; nil keeps the current one.
    private var worldspace: String?

    private var game: any AgentWorldHost {
        adapter.game
    }

    public init(adapter: AgentWorldAdapter, target: AgentTeleportTarget) throws(AgentFailure) {
        self.adapter = adapter
        guard
            let gameSession = adapter.game.gameSession,
            let streamer = adapter.game.streamer
        else {
            throw adapter.notReady()
        }
        guard streamer.transitionInFlight == nil else {
            throw AgentFailure(.notReady, "a door transition is still loading")
        }
        switch target {
        case let .position(position, world):
            worldspace = world
            phase = .settling(untilFrame: 0)
            place(
                at: position,
                gameSession: gameSession,
                streamer: streamer,
                leavingInterior: world != nil
            )
            phase = settling()
        case let .reference(text):
            let reference: AgentReference
            do throws(AgentFailure) {
                reference = try adapter.resolveReference(text)
            } catch where error.code == .notFound {
                guard let formID = FormID(token: text) else { throw error }
                lookedUpReference = text
                phase = .lookingUp
                try startReferenceLookup(formID)
                return
            }
            guard let feet = Self.standingSpot(of: reference.key, game: adapter.game) else {
                throw AgentFailure(.notFound, "the reference has no placement")
            }
            phase = .settling(untilFrame: 0)
            place(
                at: feet,
                gameSession: gameSession,
                streamer: streamer,
                leavingInterior: false
            )
            phase = settling()
        case let .grid(x, y, world):
            worldspace = world
            phase = .lookingUp
            enterGrid(CellCoordinate(x: x, y: y))
        case let .cell(editorID):
            phase = .lookingUp
            try startLookup { CellDirectory.find(editorID: editorID, in: $0) }
        }
    }

    /// A loaded save's place: its cell loads first, then the player stands where the save was made.
    public init(
        adapter: AgentWorldAdapter, place: SavePlayerPlace, pitch: Float? = nil
    ) throws(AgentFailure) {
        self.adapter = adapter
        guard let streamer = adapter.game.streamer, adapter.game.renderer != nil else {
            throw adapter.notReady()
        }
        guard streamer.transitionInFlight == nil else {
            throw AgentFailure(.notReady, "a door transition is still loading")
        }
        exactFeet = place.feet
        exactYaw = place.yaw
        exactPitch = pitch
        worldspace = place.worldspace
        phase = .lookingUp
        switch place.cell {
        case .exterior:
            enterGrid(CellCoordinate(containing: place.feet))
        case let .interior(cell):
            try startLookup { CellDirectory.find(formID: cell, in: $0) }
        }
    }

    public var wait: AgentWait {
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
                adapter.isWorldLoaded else { return .wait }
            snapToGround(in: grid)
            phase = settling()
        case let .loadingInterior(cell):
            guard
                streamer.transitionInFlight == nil,
                streamer.interiorScene?.location == .interior(cell)
            else { return .wait }
            useCOCMarker(in: streamer.interiorScene?.references, grid: nil)
            useLoadedReference()
            if let exactFeet, let gameSession = game.gameSession {
                place(
                    at: exactFeet,
                    gameSession: gameSession,
                    streamer: streamer,
                    leavingInterior: false
                )
            }
            phase = settling()
        case let .settling(untilFrame):
            guard
                adapter.isWorldLoaded,
                game.simulationClock.frame >= untilFrame else { return .wait }
            // Boots on the ground: a placed height above the floor must not end in a fall.
            game.gameSession?.settlePlayerOnGround()
            return try .done(.success(adapter.query(.player)))
        }
        return .wait
    }

    private func settling() -> Phase {
        .settling(untilFrame: game.simulationClock.frame + Self.settleFrames)
    }

    // MARK: - Cells by editor ID

    private func startLookup(
        _ find: @escaping @Sendable (LoadOrderPlugins) -> CellDirectoryEntry?
    ) throws(AgentFailure) {
        guard let root = adapter.dataRoot else {
            throw AgentFailure(.notReady, "no game data is loaded")
        }
        Task { [weak self] in
            let result = await Self.findCell(find, in: root)
            self?.lookup = result
        }
    }

    private func finishLookup() throws(AgentFailure) {
        if let referenceLookup {
            self.referenceLookup = nil
            switch try referenceLookup.get() {
            case nil:
                throw AgentFailure(.notFound, "no reference with that FormID in the load order")
            case let .exterior(found):
                exactFeet = found.placement.position
                worldspace = found.worldspace
                enterGrid(CellCoordinate(containing: found.placement.position))
                return
            case let .interior(feet, entry):
                exactFeet = feet
                lookup = .success(entry)
            }
        }
        guard let lookup else { return }
        guard let entry = try lookup.get() else {
            throw AgentFailure(.notFound, "no such cell in the load order")
        }
        switch entry {
        case let .exterior(_, world, grid):
            worldspace = world
            enterGrid(grid)
        case let .interior(cell, entryDoor):
            guard let entryDoor else {
                throw AgentFailure(.unsupported, "the interior has no door to enter through")
            }
            game.streamer?.isHeld = false
            guard game.streamer?.requestDoorTransition(from: entryDoor) == true else {
                throw AgentFailure(.notReady, "a door transition is still loading")
            }
            phase = .loadingInterior(cell)
        }
    }

    // MARK: - Moving the player

    private func enterGrid(_ grid: CellCoordinate) {
        guard let gameSession = game.gameSession, let streamer = game.streamer else { return }
        let center = Self.center(of: grid)
        // The height is a guess until the cell's terrain loads; then the
        // player is put on the ground.
        let height = streamer.sampleTerrain(at: center)?.height ?? 0
        place(at: SIMD3(center, height), gameSession: gameSession, streamer: streamer)
        phase = .loadingGrid(grid)
    }

    private func snapToGround(in grid: CellCoordinate) {
        guard let gameSession = game.gameSession, let streamer = game.streamer else { return }
        useCOCMarker(in: streamer.composition.cells[grid]?.references, grid: grid)
        useLoadedReference()
        if let exactFeet {
            place(at: exactFeet, gameSession: gameSession, streamer: streamer)
            return
        }
        let center = Self.center(of: grid)
        // A city world hides the terrain under its streets, so its collision is the ground.
        let feet = streamer.sampleTerrain(at: center).map { SIMD3(center, $0.height) }
            ?? streamer.topCollisionSurface(at: center)
        guard let feet else { return }
        place(at: feet, gameSession: gameSession, streamer: streamer)
    }

    /// Stands the player where `coc` would, unless the request named an exact spot.
    /// An exterior cell's index also holds persistent references from other cells.
    private func useCOCMarker(in references: RuntimeReferenceIndex?, grid: CellCoordinate?) {
        guard exactFeet == nil, let references else { return }
        let placed = references.sortedEntries().compactMap(\.placedReference).filter { ref in
            grid.map { CellCoordinate(containing: ref.placement.position) == $0 } ?? true
        }
        guard let marker = CenterOnCellMarker.placement(in: placed) else { return }
        exactFeet = marker.position
        exactYaw = marker.rotation.z
    }

    /// A position or a reference stays in the current cell, because interior
    /// coordinates are local to their cell. A grid teleport leaves the interior.
    private func place(
        at feet: SIMD3<Float>,
        gameSession: any GameSessionPort,
        streamer: any CellStreamerPort,
        leavingInterior: Bool = true
    ) {
        let renderer = gameSession.renderer
        // The move is a picked start, so the world held by the main menu loads now.
        streamer.isHeld = false
        let rotation = SIMD3<Float>(exactPitch ?? 0, 0, exactYaw ?? gameSession.freeFlyCamera.yaw)
        let camera = SceneCamera.teleport(placement: .init(position: feet, rotation: rotation))
        if let worldspace, worldspace != streamer.worldspaceEditorID {
            streamer.enterWorldspace(worldspace, camera: camera)
        } else if leavingInterior, streamer.interiorScene != nil {
            streamer.leaveInterior(camera: camera)
        } else {
            streamer.moveStart(to: feet)
            renderer.camera = camera
            gameSession.reseedMovement(camera: camera)
        }
    }
}

extension AgentTeleportJob {
    /// In front of a looked-up actor once its cell has loaded, not inside it.
    private func useLoadedReference() {
        guard let text = lookedUpReference else { return }
        lookedUpReference = nil
        do throws(AgentFailure) {
            let reference = try adapter.resolveReference(text)
            if let spot = Self.standingSpot(of: reference.key, game: game) {
                exactFeet = spot
            }
        } catch {
            return
        }
    }

    // MARK: - References outside the loaded cells

    private func startReferenceLookup(_ formID: FormID) throws(AgentFailure) {
        guard let root = adapter.dataRoot else {
            throw AgentFailure(.notReady, "no game data is loaded")
        }
        Task { [weak self] in
            let result = await Self.findReference(formID, in: root)
            self?.referenceLookup = result
        }
    }

    @concurrent
    nonisolated private static func findCell(
        _ find: @Sendable (LoadOrderPlugins) -> CellDirectoryEntry?,
        in root: GameDataRoot
    ) async -> Result<CellDirectoryEntry?, AgentFailure> {
        do {
            return try .success(find(loadOrder(root)))
        } catch {
            return .failure(AgentFailure(.failed, "could not read the load order: \(error)"))
        }
    }

    /// The same plugins and FormID space the session reads.
    nonisolated private static func loadOrder(_ root: GameDataRoot) throws -> LoadOrderPlugins {
        try ActiveLoadOrder.open(root: root).plugins
    }

    /// An interior reference also needs its cell's way in, found in the same read.
    nonisolated private enum ReferenceLookup: Sendable {
        case exterior(ExteriorPlacement)
        case interior(feet: SIMD3<Float>, entry: CellDirectoryEntry?)
    }

    @concurrent
    nonisolated private static func findReference(
        _ formID: FormID,
        in root: GameDataRoot
    ) async -> Result<ReferenceLookup?, AgentFailure> {
        do {
            let plugins = try loadOrder(root)
            switch CellDirectory.location(of: formID, in: plugins) {
            case nil:
                return .success(nil)
            case let .exterior(found):
                return .success(.exterior(found))
            case let .interior(cell, placement):
                let entry = CellDirectory.find(formID: cell, in: plugins)
                return .success(.interior(feet: placement.position, entry: entry))
            }
        } catch {
            return .failure(AgentFailure(.failed, "could not read the load order: \(error)"))
        }
    }

    private static func center(of grid: CellCoordinate) -> SIMD2<Float> {
        SIMD2(
            (Float(grid.x) + 0.5) * CellCoordinate.cellSize,
            (Float(grid.y) + 0.5) * CellCoordinate.cellSize
        )
    }

    /// Next to a loaded actor, where it stands now, or on a loaded reference.
    private static func standingSpot(of key: ReferenceKey, game: any AgentWorldHost)
        -> SIMD3<Float>?
    {
        if let actor = game.actorWorld.combatActor(key: key) {
            // Rotation Z counts clockwise from north, so forward is (sin, cos).
            let front = SIMD2<Float>(sin(actor.facing), cos(actor.facing)) * actorStandOff
            return actor.feet + SIMD3(front, 0)
        }
        let entry = game.streamer?.referenceEntry(key: key)
        return entry?.placedReference?.placement.position
            ?? entry?.placedActor?.placement.position
    }

    /// About two arm lengths: close enough to talk, far enough not to overlap.
    private static let actorStandOff: Float = 100
}

extension AgentTeleportJob: AgentTeleportJobPort {}
