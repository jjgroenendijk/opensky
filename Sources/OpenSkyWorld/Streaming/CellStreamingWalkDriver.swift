// Exterior half of the walk benchmark driver.

import OpenSkyCells
import OpenSkyNavigation
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyTerrain
import OpenSkyWorldInterface
import simd

@MainActor
public final class CellStreamingWalkDriver {
    public static let inputTimeStep: Float = 1 / 30
    public let gameSession: GameSession
    public let runner: SerialCellBuildRunner
    public let streamer: CellStreamer
    public let swapError = WalkBenchmarkSceneSwapErrorBox()
    public let configuration: CellStreamingWalkBenchmarkConfiguration
    public var phase = WalkBenchmarkPhase.loadExterior
    public var phaseFrames = 0
    public var physicsFrameMask: [Bool] = []
    public var routeFrameCount = 0
    public var controllerState = WalkBenchmarkControllerState()
    public var stepStartHeight: Float?
    public var maximumStepHeight: Float?
    public var interiorArrival: SIMD2<Float>?
    public var interiorRoute: [SIMD2<Float>] = []
    public var interiorRouteIndex = 0
    public var interiorDistance: Float = 0
    public var navigationState = WalkBenchmarkNavigationState()

    public var renderer: Renderer {
        gameSession.renderer
    }

    public init(
        gameSession: GameSession,
        provider: sending any CellSceneProvider,
        configuration: CellStreamingWalkBenchmarkConfiguration
    ) {
        self.gameSession = gameSession
        let renderer = gameSession.renderer
        self.configuration = configuration
        runner = SerialCellBuildRunner(provider: provider)
        streamer = CellStreamer(
            center: WalkPathRoute.startCell,
            runner: runner
        ) { [renderer, swapError] scene, camera in
            do {
                try renderer.setScene(scene, camera: camera)
            } catch {
                swapError.error = error
            }
        }
        gameSession.movementMode = .walk
        renderer.attachTextureStreaming(to: runner)
    }

    public func step() throws -> Bool {
        physicsFrameMask.append(phase.physicsActive)
        if phase.physicsActive {
            routeFrameCount += 1
        }
        try validateBuildsAndSwap()
        phaseFrames += 1
        switch phase {
        case .loadExterior:
            try loadExterior()
        case .settleStart:
            try settleStart()
        case let .walkExterior(index):
            try walkExterior(index: index)
        case .requestEntry:
            try requestEntry()
        case .waitInterior:
            try waitInterior()
        case .settleInterior:
            try settleInterior()
        case .crossInterior:
            try crossInterior()
        case .returnInterior:
            try returnInterior()
        case .requestExit:
            try requestExit()
        case .waitExterior:
            try waitExterior()
        case .settleExteriorReturn:
            return try settleExteriorReturn()
        }
        return false
    }

    public func result(render: OffscreenBenchResult) throws -> CellStreamingWalkBenchmarkResult {
        let stepGain = (maximumStepHeight ?? 0) - (stepStartHeight ?? 0)
        guard stepGain >= WalkPathRoute.minimumExteriorStepGain else {
            throw CellStreamingWalkBenchmarkError.stepNotClimbed(stepGain)
        }
        guard interiorDistance >= WalkPathRoute.interiorCrossingDistance * 0.8 else {
            throw CellStreamingWalkBenchmarkError.interiorNotCrossed(interiorDistance)
        }
        return CellStreamingWalkBenchmarkResult(
            render: render,
            physicsRender: CellStreamingWalkBenchmark.activePhysicsResult(
                render: render,
                frameMask: physicsFrameMask
            ),
            exteriorStepGain: stepGain,
            interiorDistance: interiorDistance,
            finalFeetPosition: gameSession.walkController.feetPosition
        )
    }

    public func loadExterior() throws {
        let center = CellGridManager.cellCenter(of: WalkPathRoute.startCell)
        streamer.update(cameraPosition: center)
        guard Self.isSettled(streamer) else {
            try timeout(limit: configuration.maxFrames)
            return
        }
        let start = WalkPathRoute.exteriorWaypoints[0]
        guard let ground = streamer.sampleTerrain(at: start) else {
            throw CellStreamingWalkBenchmarkError.noStartGround(start)
        }
        let feet = SIMD3(start.x, start.y, ground.height)
        gameSession.freeFlyCamera.position = feet
            + SIMD3<Float>(0, 0, PlayerCapsule.standard.eyeHeight)
        gameSession.freeFlyCamera.yaw = WalkPathRoute.yaw(
            from: start,
            to: WalkPathRoute.exteriorWaypoints[1]
        )
        gameSession.freeFlyCamera.pitch = 0
        gameSession.walkController.reset(cameraPosition: gameSession.freeFlyCamera.position)
        controllerState.lastGroundedHeight = ground.height
        changePhase(.settleStart)
    }

    public func settleStart() throws {
        updateController(moveForward: 0)
        streamer.update(cameraPosition: gameSession.freeFlyCamera.position)
        try validateController()
        if gameSession.walkController.isGrounded {
            changePhase(.walkExterior(1))
        } else {
            try timeout(limit: 120)
        }
    }

    public func walkExterior(index: Int) throws {
        let target = WalkPathRoute.exteriorWaypoints[index]
        drive(toward: target, routeIndex: index)
        streamer.update(cameraPosition: gameSession.freeFlyCamera.position)
        try validateController()
        if index == WalkPathRoute.exteriorWaypoints.count - 1 {
            let height = gameSession.walkController.feetPosition.z
            stepStartHeight = stepStartHeight ?? height
            maximumStepHeight = max(maximumStepHeight ?? height, height)
        }
        guard distance(to: target) <= WalkPathRoute.waypointTolerance else {
            try timeout(limit: WalkPathRoute.maximumWaypointFrames)
            return
        }
        guard gameSession.walkController.isGrounded else { return }
        if index + 1 < WalkPathRoute.exteriorWaypoints.count {
            changePhase(.walkExterior(index + 1))
        } else {
            changePhase(.requestEntry)
        }
    }

    public func requestEntry() throws {
        let door = streamer.composition.nearestDoor(
            to: gameSession.freeFlyCamera.position,
            within: CellStreamer.doorActivationRadius
        )
        guard door?.reference == WalkPathRoute.farmDoor else {
            throw CellStreamingWalkBenchmarkError.wrongDoor(
                expected: WalkPathRoute.farmDoor,
                actual: door?.reference
            )
        }
        let interactionRay = door.flatMap {
            InteractionRay(
                origin: gameSession.freeFlyCamera.position,
                direction: $0.position - gameSession.freeFlyCamera.position
            )
        }
        streamer.update(
            cameraPosition: gameSession.freeFlyCamera.position,
            interactionRay: interactionRay,
            activate: true
        )
        guard streamer.interactionTarget?.interaction.reference == WalkPathRoute.farmDoor else {
            throw CellStreamingWalkBenchmarkError.wrongDoor(
                expected: WalkPathRoute.farmDoor,
                actual: streamer.interactionTarget?.interaction.reference
            )
        }
        changePhase(.waitInterior)
    }
}
