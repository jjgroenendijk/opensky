// Exterior half of M4.5 walk benchmark driver.

import simd

@MainActor
final class CellStreamingWalkDriver {
    static let inputTimeStep: Float = 1 / 30
    let renderer: Renderer
    let runner: SerialCellBuildRunner
    let streamer: CellStreamer
    let swapError = WalkBenchmarkSceneSwapErrorBox()
    let configuration: CellStreamingWalkBenchmarkConfiguration
    var phase = WalkBenchmarkPhase.loadExterior
    var phaseFrames = 0
    var physicsFrameMask: [Bool] = []
    var routeFrameCount = 0
    var lastGroundedHeight: Float?
    var airborneFrames = 0
    var stepStartHeight: Float?
    var maximumStepHeight: Float?
    var interiorArrival: SIMD2<Float>?
    var interiorTarget: SIMD2<Float>?
    var interiorDistance: Float = 0
    var bestNavigationDistance = Float.greatestFiniteMagnitude
    var stalledNavigationFrames = 0
    var avoidanceFrames = 0
    var avoidanceAttempt = 0
    var avoidanceDirection: Float = 1

    init(
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

    func step() throws -> Bool {
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

    func result(render: OffscreenBenchResult) throws -> CellStreamingWalkBenchmarkResult {
        let activeTimes = zip(render.frameMS, physicsFrameMask).compactMap { time, active in
            active ? time : nil
        }
        let stepGain = (maximumStepHeight ?? 0) - (stepStartHeight ?? 0)
        guard stepGain >= WalkPathRoute.minimumExteriorStepGain else {
            throw CellStreamingWalkBenchmarkError.stepNotClimbed(stepGain)
        }
        guard interiorDistance >= WalkPathRoute.interiorCrossingDistance * 0.8 else {
            throw CellStreamingWalkBenchmarkError.interiorNotCrossed(interiorDistance)
        }
        return CellStreamingWalkBenchmarkResult(
            render: render,
            physicsRender: OffscreenBenchResult(
                frameMS: activeTimes,
                windowSummaries: render.windowSummaries
            ),
            routeFrameCount: routeFrameCount,
            exteriorStepGain: stepGain,
            interiorDistance: interiorDistance,
            finalFeetPosition: renderer.walkController.feetPosition
        )
    }

    func loadExterior() throws {
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
        lastGroundedHeight = ground.height
        changePhase(.settleStart)
    }

    func settleStart() throws {
        updateController(moveForward: 0)
        streamer.update(cameraPosition: renderer.freeFlyCamera.position)
        try validateController()
        if renderer.walkController.isGrounded {
            changePhase(.walkExterior(1))
        } else {
            try timeout(limit: 120)
        }
    }

    func walkExterior(index: Int) throws {
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

    func requestEntry() throws {
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
        streamer.update(cameraPosition: renderer.freeFlyCamera.position, activate: true)
        changePhase(.waitInterior)
    }
}
