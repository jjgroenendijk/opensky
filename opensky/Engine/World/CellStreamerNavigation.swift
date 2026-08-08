// Streamed navigation reconciliation and query surface (issue #200). Like
// CellStreamerPhysics, this derives lifetime from resident scenes each frame:
// coverage swaps, door transitions and state rebuilds therefore need no
// navigation-specific callbacks.

import simd

struct CellStreamerNavigationState {
    var graph = RuntimeNavigationGraph()
    var repathRequests: [NavigationRepathRequest] = []
    var onRepath: ((NavigationRepathResponse) -> Void)?
    /// Most recently completed path, retained only as the debug-overlay source.
    var lastPath: NavigationPath?
}

extension CellStreamer {
    /// Named frame budget: a crowd may invalidate together after an unload,
    /// but only this many queued paths can consume A* work in one frame.
    static let maximumNavigationRepathsPerFrame = 2

    func navigationProjection(
        of point: SIMD3<Float>,
        searchRadius: Float = NavigationPathQuery.defaultProjectionRadius
    ) -> NavigationProjectionResult {
        reconcileNavigation()
        return navigationState.graph.projection(of: point, searchRadius: searchRadius)
    }

    /// Immediate query for user-driven and inspection callers. Actor followers
    /// use the queued repath surface below so a crowd cannot spike one frame.
    func findPath(_ query: NavigationPathQuery) -> NavigationPathResult {
        reconcileNavigation()
        let result = navigationState.graph.findPath(query)
        rememberNavigationPath(from: result)
        return result
    }

    func navigationPathIsCurrent(
        _ path: NavigationPath,
        target: SIMD3<Float>,
        targetMoveTolerance: Float = NavigationPathQuery.defaultTargetMoveTolerance
    ) -> Bool {
        reconcileNavigation()
        return navigationState.graph.pathIsCurrent(
            path, target: target, targetMoveTolerance: targetMoveTolerance
        )
    }

    /// Queues one replacement per follower only when an unload/rebuild or a
    /// sufficiently moved target invalidated its prior corridor.
    func requestNavigationRepathIfNeeded(
        identifier: UInt64,
        query: NavigationPathQuery,
        previousPath: NavigationPath,
        targetMoveTolerance: Float = NavigationPathQuery.defaultTargetMoveTolerance
    ) {
        reconcileNavigation()
        guard
            !navigationState.graph.pathIsCurrent(
                previousPath,
                target: query.target,
                targetMoveTolerance: targetMoveTolerance
            ) else { return }
        requestNavigationRepath(NavigationRepathRequest(identifier: identifier, query: query))
    }

    func requestNavigationRepath(_ request: NavigationRepathRequest) {
        navigationState.repathRequests.removeAll { $0.identifier == request.identifier }
        navigationState.repathRequests.append(request)
    }

    func advanceWorldSystems(frameTime: Float, player: PlayerCapsuleState?) {
        advancePhysics(frameTime: frameTime, player: player)
        advanceNavigation()
    }

    func advanceNavigation() {
        reconcileNavigation()
        let count = min(
            Self.maximumNavigationRepathsPerFrame,
            navigationState.repathRequests.count
        )
        guard count > 0 else { return }
        let requests = Array(navigationState.repathRequests.prefix(count))
        navigationState.repathRequests.removeFirst(count)
        for request in requests {
            let result = navigationState.graph.findPath(request.query)
            rememberNavigationPath(from: result)
            navigationState.onRepath?(NavigationRepathResponse(
                identifier: request.identifier,
                result: result
            ))
        }
    }

    /// Adds every newly resident/rebuilt cell and drops every departed one.
    func reconcileNavigation() {
        let resident = residentNavigationScenes()
        navigationState.graph.retainCells(Set(resident.keys))
        for location in resident.keys.sorted(by: CellSceneLocation.isOrderedBefore) {
            guard let scene = resident[location] else { continue }
            guard navigationState.graph.installedCells[location] != scene.stateSequence else {
                continue
            }
            navigationState.graph.setCell(location, scene: scene)
        }
    }

    private func residentNavigationScenes() -> [CellSceneLocation: CellScene] {
        var resident: [CellSceneLocation: CellScene] = [:]
        if let interiorScene, let location = interiorScene.location {
            resident[location] = interiorScene
        } else {
            for scene in composition.cells.values {
                guard let location = scene.location else { continue }
                resident[location] = scene
            }
        }
        return resident
    }

    private func rememberNavigationPath(from result: NavigationPathResult) {
        switch result {
        case let .path(path):
            navigationState.lastPath = path
        case .miss:
            navigationState.lastPath = nil
        }
    }
}
