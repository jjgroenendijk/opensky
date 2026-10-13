// Steps every actor behavior graph of the install, fires each event the graph
// declares, and sorts the generator and modifier classes the data uses into done,
// left, and never reached. `openskycli gaps` prints it. Class names and counts only.

import Foundation
import OpenSkyFormatsAnimation
import OpenSkyGameData

nonisolated public struct BehaviorGapSweep {
    public static let actorsPrefix = "meshes\\actors\\"
    public static let idleUpdates = 30
    public static let updatesPerEvent = 3
    public static let timestep: Float = 1.0 / 30.0

    /// Node class -> objects of it in the swept graphs.
    public private(set) var classCounts: [String: Int] = [:]
    public private(set) var reachedClasses: Set<String> = []
    public private(set) var tally = BehaviorTally(nameLimit: 4096)
    public private(set) var graphCount = 0
    public private(set) var eventsFired = 0
    public private(set) var failures: [String] = []
    /// File sets whose skeleton is missing or does not load.
    public private(set) var foldersWithoutSkeleton: [String] = []

    public init() {}

    /// A class the evaluator runs as a node, by Havok's naming.
    public static func isNodeClass(_ name: String) -> Bool {
        name.hasSuffix("Generator") || name.hasSuffix("Modifier")
            || name == "hkbStateMachine" || name == "hkbModifierList"
    }

    // MARK: - Classification

    /// Node class -> why the evaluator does not fully run it. The first reason wins.
    public var gapReasons: [String: String] {
        let gaps = tally.unevaluatedGenerators.keys.map { ($0, "not evaluated") }
            + tally.partialGenerators.keys.map { ($0, "partly evaluated") }
            + tally.passthroughModifiers.keys.map { ($0, "passed through") }
            + tally.undecodableObjects.keys.map { ($0, "not decoded") }
        var reasons: [String: String] = [:]
        for (name, reason) in gaps where reasons[name] == nil {
            reasons[name] = reason
        }
        return reasons
    }

    /// Node classes with a gap, with the objects of each in the data.
    public var leftClasses: [(name: String, count: Int)] {
        Self.ranked(gapReasons.map { ("\($0.key) (\($0.value))", classCounts[$0.key] ?? 0) })
    }

    /// Node classes reached with no gap noted.
    public var doneClasses: [String] {
        reachedClasses.subtracting(gapReasons.keys).sorted()
    }

    /// Node classes in the data that no update reached, so nothing is known of them.
    public var unreachedClasses: [(name: String, count: Int)] {
        let reasons = gapReasons
        return Self.ranked(classCounts.filter {
            !reachedClasses.contains($0.key) && reasons[$0.key] == nil
        }.map { ($0.key, $0.value) })
    }

    private static func ranked(_ rows: [(String, Int)]) -> [(name: String, count: Int)] {
        rows.map { (name: $0.0, count: $0.1) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }

    // MARK: - Running

    /// Every behavior file under `meshes\actors\`, each set with its own skeleton
    /// and clips.
    public static func run(fileSystem: VirtualFileSystem) -> BehaviorGapSweep {
        var sweep = BehaviorGapSweep()
        let paths = fileSystem.archiveEntries().map(\.path).filter { $0.hasPrefix(actorsPrefix) }
        for set in fileSets(in: paths) {
            guard let skeleton = set.skeleton.flatMap({ loadSkeleton($0, fileSystem) }) else {
                sweep.foldersWithoutSkeleton.append(set.name)
                continue
            }
            let clips = InstallBehaviorClipSource(fileSystem: fileSystem, paths: set.animations)
            for path in set.behaviors {
                do {
                    try sweep.step(path, fileSystem: fileSystem, skeleton: skeleton, clips: clips)
                } catch {
                    sweep.failures.append("\(path): \(error)")
                }
            }
        }
        return sweep
    }

    private mutating func step(
        _ path: String,
        fileSystem: VirtualFileSystem,
        skeleton: BehaviorSkeleton,
        clips: InstallBehaviorClipSource
    ) throws {
        let objectGraph =
            try HKXObjectGraph(file: HKXFile(data: fileSystem.contents(forPath: path)))
        guard let graph = HKBBehaviorGraph.graphs(in: objectGraph).first else { return }
        graphCount += 1
        for name in objectGraph.objectRefs.compactMap(\.className) where Self.isNodeClass(name) {
            classCounts[name, default: 0] += 1
        }
        let instance = BehaviorGraphInstance(
            graph: graph, in: objectGraph, skeleton: skeleton, clips: clips, tallyNameLimit: 4096
        )
        let source = HKXBehaviorObjectSource(graph: objectGraph)
        instance.activate()
        update(instance, times: Self.idleUpdates, source: source)
        for name in instance.events.names.compactMap(\.self)
            where instance.raiseEvent(named: name)
        {
            eventsFired += 1
            update(instance, times: Self.updatesPerEvent, source: source)
        }
        instance.deactivate()
        tally.merge(instance.tally)
    }

    private mutating func update(
        _ instance: BehaviorGraphInstance, times: Int, source: HKXBehaviorObjectSource
    ) {
        for _ in 0 ..< times {
            _ = instance.update(deltaTime: Self.timestep)
            for target in instance.reachedThisUpdate {
                if let name = source.className(at: target) {
                    reachedClasses.insert(name)
                }
            }
        }
    }

    private static func loadSkeleton(
        _ path: String,
        _ fileSystem: VirtualFileSystem
    ) -> BehaviorSkeleton? {
        guard
            let data = try? fileSystem.contents(forPath: path),
            let file = try? HKXFile(data: data),
            let rig = (try? HKASkeleton.skeletons(in: file))?.first
        else {
            return nil
        }
        return BehaviorSkeleton(rig)
    }
}
