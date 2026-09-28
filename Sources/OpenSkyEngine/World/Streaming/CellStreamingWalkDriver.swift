// Exterior half of M4.5 walk benchmark driver.

import OpenSkyPhysics
import simd

@MainActor
public final class CellStreamingWalkDriver {
    public static let inputTimeStep: Float = 1 / 30
    public let renderer: Renderer
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

    public init(
        renderer: Renderer,
        provider: any CellSceneProvider,
        configuration: CellStreamingWalkBenchmarkConfiguration
    ) {
        self.renderer = renderer
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
        renderer.movementMode = .walk
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
            routeFrameCount: routeFrameCount,
            exteriorStepGain: stepGain,
            interiorDistance: interiorDistance,
            finalFeetPosition: renderer.walkController.feetPosition
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
        renderer.freeFlyCamera.position = feet
            + SIMD3<Float>(0, 0, PlayerCapsule.standard.eyeHeight)
        renderer.freeFlyCamera.yaw = WalkPathRoute.yaw(
            from: start,
            to: WalkPathRoute.exteriorWaypoints[1]
        )
        renderer.freeFlyCamera.pitch = 0
        renderer.walkController.reset(cameraPosition: renderer.freeFlyCamera.position)
        controllerState.lastGroundedHeight = ground.height
        changePhase(.settleStart)
    }

    public func settleStart() throws {
        updateController(moveForward: 0)
        streamer.update(cameraPosition: renderer.freeFlyCamera.position)
        try validateController()
        if renderer.walkController.isGrounded {
            changePhase(.walkExterior(1))
        } else {
            try timeout(limit: 120)
        }
    }

    public func walkExterior(index: Int) throws {
        let target = WalkPathRoute.exteriorWaypoints[index]
        drive(toward: target, routeIndex: index)
        streamer.update(cameraPosition: renderer.freeFlyCamera.position)
        try validateController()
        if index == WalkPathRoute.exteriorWaypoints.count - 1 {
            let height = renderer.walkController.feetPosition.z
            stepStartHeight = stepStartHeight ?? height
            maximumStepHeight = max(maximumStepHeight ?? height, height)
        }
        guard distance(to: target) <= WalkPathRoute.waypointTolerance else {
            try timeout(limit: WalkPathRoute.maximumWaypointFrames)
            return
        }
        guard renderer.walkController.isGrounded else { return }
        if index + 1 < WalkPathRoute.exteriorWaypoints.count {
            changePhase(.walkExterior(index + 1))
        } else {
            changePhase(.requestEntry)
        }
    }

    public func requestEntry() throws {
        let door = streamer.composition.nearestDoor(
            to: renderer.freeFlyCamera.position,
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
                origin: renderer.freeFlyCamera.position,
                direction: $0.position - renderer.freeFlyCamera.position
            )
        }
        streamer.update(
            cameraPosition: renderer.freeFlyCamera.position,
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
