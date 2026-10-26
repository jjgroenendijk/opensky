// Steps one actor behaviour graph of the install, raises named events in order, and
// records the states each event reaches. `openskycli hkx --raise` prints it, so a
// reader can check which event moves a graph where, such as a dragon's take-off.

import Foundation
import OpenSkyFormatsAnimation
import OpenSkyGameData

nonisolated public enum BehaviorEventProbe {
    /// What the graph did after one raised event, or after the idle updates.
    public struct Step: Equatable, Sendable {
        /// Nil for the idle updates before the first event.
        public let event: String?
        /// False when the graph declares no such event.
        public let accepted: Bool
        /// The innermost active state of each running state machine.
        public let states: [String]
        public let fired: [String]
    }

    nonisolated public enum Failure: Error, Equatable, CustomStringConvertible {
        case notActorBehavior(String)
        case noSkeleton(String)
        case noGraph(String)

        public var description: String {
            switch self {
            case let .notActorBehavior(path): "\(path) is not in a behaviors folder"
            case let .noSkeleton(set): "no skeleton loads for \(set)"
            case let .noGraph(path): "\(path) holds no behavior graph"
            }
        }
    }

    public static let timestep: Float = 1.0 / 30.0

    /// Runs `idleUpdates`, then each event followed by `updatesPerEvent` updates.
    /// `variables` are written before every update.
    public static func run(
        path: String,
        events: [String],
        variables: [String: Float] = [:],
        idleUpdates: Int = 30,
        updatesPerEvent: Int = 30,
        fileSystem: VirtualFileSystem
    ) throws -> [Step] {
        let key = path.lowercased().replacingOccurrences(of: "/", with: "\\")
        let paths = fileSystem.archiveEntries().map(\.path)
        guard let set = BehaviorGapSweep.fileSets(in: paths).first(where: {
            $0.behaviors.contains(key)
        }) else { throw Failure.notActorBehavior(path) }
        guard
            let skeletonPath = set.skeleton,
            let data = try? fileSystem.contents(forPath: skeletonPath),
            let rig = (try? HKASkeleton.skeletons(in: HKXFile(data: data)))?.first
        else { throw Failure.noSkeleton(set.name) }
        let objects = try HKXObjectGraph(file: HKXFile(data: fileSystem.contents(forPath: key)))
        guard let graph = HKBBehaviorGraph.graphs(in: objects).first else {
            throw Failure.noGraph(path)
        }
        let instance = BehaviorGraphInstance(
            graph: graph, in: objects, skeleton: BehaviorSkeleton(rig),
            clips: InstallBehaviorClipSource(fileSystem: fileSystem, paths: set.animations)
        )
        instance.activate()
        var steps = [advance(instance, event: nil, accepted: true, idleUpdates, variables)]
        for event in events {
            let accepted = instance.raiseEvent(named: event)
            steps.append(
                advance(instance, event: event, accepted: accepted, updatesPerEvent, variables)
            )
        }
        instance.deactivate()
        return steps
    }

    private static func advance(
        _ instance: BehaviorGraphInstance, event: String?, accepted: Bool, _ updates: Int,
        _ variables: [String: Float]
    ) -> Step {
        var fired: [String] = []
        for _ in 0 ..< updates {
            for (name, value) in variables.sorted(by: { $0.key < $1.key }) {
                instance.setVariable(.real(value), named: name)
            }
            let result = instance.update(deltaTime: timestep)
            fired += result.firedEvents.compactMap(\.name) + result.unboundEvents
        }
        let states = instance.activeStates.map { state in
            "\(state.machineName ?? "?"): \(state.stateName ?? String(state.stateId))"
        }
        return Step(event: event, accepted: accepted, states: states, fired: fired)
    }
}
