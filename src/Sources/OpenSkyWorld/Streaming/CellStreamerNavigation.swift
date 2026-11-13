// Streamed navigation reconciliation and query surface. Like
// CellStreamerPhysics, this derives lifetime from resident scenes each frame:
// coverage swaps, door transitions and state rebuilds therefore need no
// navigation-specific callbacks.

import OpenSkyCells
import OpenSkyGameData
public import OpenSkyNavigation
import OpenSkyPlayer
public import OpenSkyWorldInterface
import simd

public struct CellStreamerNavigationState {
    public var graph = RuntimeNavigationGraph()
    public var repathRequests: [NavigationRepathRequest] = []
    public var onRepath: ((NavigationRepathResponse) -> Void)?
    /// Most recently completed path, retained only as the debug-overlay source.
    public var lastPath: NavigationPath?
}

extension CellStreamer.NavigationSteps {
    /// Named frame budget: a crowd may invalidate together after an unload,
    /// but only this many queued paths can consume A* work in one frame.
    public static let maximumNavigationRepathsPerFrame = 2

    /// Immediate query for user-driven and inspection callers. Actor followers
    /// use the queued repath surface below so a crowd cannot spike one frame.
    public func findPath(_ query: NavigationPathQuery) -> NavigationPathResult {
        reconcileNavigation()
        let result = streamer.navigationState.graph.findPath(query)
        rememberNavigationPath(from: result)
        return result
    }

    public func navigationPathIsCurrent(
        _ path: NavigationPath,
        target: SIMD3<Float>,
        targetMoveTolerance: Float = NavigationPathQuery.defaultTargetMoveTolerance
    ) -> Bool {
        reconcileNavigation()
        return streamer.navigationState.graph.pathIsCurrent(
            path, target: target, targetMoveTolerance: targetMoveTolerance
        )
    }

    public func requestNavigationRepath(_ request: NavigationRepathRequest) {
        streamer.navigationState.repathRequests.removeAll { $0.identifier == request.identifier }
        streamer.navigationState.repathRequests.append(request)
    }

    func advanceWorldSystems(frameTime: Float, player: PlayerCapsuleState?) {
        streamer.physics.advancePhysics(frameTime: frameTime, player: player)
        streamer.actors.advanceNPCMovement(frameTime: frameTime)
        advanceNavigation()
    }

    public func advanceNavigation() {
        reconcileNavigation()
        let count = min(
            Self.maximumNavigationRepathsPerFrame,
            streamer.navigationState.repathRequests.count
        )
        guard count > 0 else { return }
        let requests = Array(streamer.navigationState.repathRequests.prefix(count))
        streamer.navigationState.repathRequests.removeFirst(count)
        for request in requests {
            let result = streamer.navigationState.graph.findPath(request.query)
            rememberNavigationPath(from: result)
            streamer.navigationState.onRepath?(NavigationRepathResponse(
                identifier: request.identifier,
                result: result
            ))
        }
    }

    /// Adds every newly resident/rebuilt cell and drops every departed one.
    public func reconcileNavigation() {
        let resident = residentNavigationScenes()
        streamer.navigationState.graph.retainCells(Set(resident.keys))
        for location in resident.keys.sorted(by: CellSceneLocation.isOrderedBefore) {
            guard
                let scene = resident[location],
                streamer.navigationState.graph.installedCells[location] != scene.stateSequence
            else {
                continue
            }
            streamer.navigationState.graph.setCell(location, scene: scene)
        }
    }

    private func residentNavigationScenes() -> [CellSceneLocation: CellScene] {
        var resident: [CellSceneLocation: CellScene] = [:]
        if let interiorScene = streamer.interiorScene, let location = interiorScene.location {
            resident[location] = interiorScene
        } else {
            for scene in streamer.composition.cells.values {
                guard let location = scene.location else { continue }
                resident[location] = scene
            }
        }
        return resident
    }

    private func rememberNavigationPath(from result: NavigationPathResult) {
        switch result {
        case let .path(path):
            streamer.navigationState.lastPath = path
        case .miss:
            streamer.navigationState.lastPath = nil
        }
    }
}
