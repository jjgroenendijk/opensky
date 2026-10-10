// A clip that is still loading: the graph holds its last pose until the clip
// arrives, and building a graph prefetches the clips its start states reach.

import EngineTesting
import Foundation
@testable import OpenSkyBehavior
@testable import OpenSkyFormatsAnimation
import OpenSkyGameData
import Testing

/// A table source whose named clips report loading until `arrive` is called.
nonisolated private final class LoadingClipSource: BehaviorClipSource {
    private let table: BehaviorClipTable
    private(set) var loading: Set<String>
    private(set) var prefetched: [String] = []

    init(table: BehaviorClipTable, loading: Set<String>) {
        self.table = table
        self.loading = loading
    }

    func arrive(_ name: String) {
        loading.remove(name)
    }

    func clip(named name: String?, bindingIndex: Int) -> (any BehaviorClip)? {
        if let name, loading.contains(name) {
            return nil
        }
        return table.clip(named: name, bindingIndex: bindingIndex)
    }

    func isLoading(named name: String?, bindingIndex _: Int) -> Bool {
        name.map(loading.contains) ?? false
    }

    func prefetch(named name: String) {
        prefetched.append(name)
    }
}

/// Bone 1 sits at 0 in state "Left" and at 10 in state "Right"; event 0 moves
/// the machine from Left to Right.
private func twoStateGraph(clips: any BehaviorClipSource) -> BehaviorGraphInstance {
    var table = BehaviorObjectTable()
    let left = table.add(
        BehaviorFixture.clipGenerator("left", animationName: "left"), at: 0x100
    )
    let right = table.add(
        BehaviorFixture.clipGenerator("right", animationName: "right"), at: 0x110
    )
    let transitions = table.add(
        BehaviorStateMachineFixture.transitions([
            BehaviorTransitionSpec(eventId: 0, toStateId: 1)
        ]),
        at: 0x200
    )
    let leftState = table.add(
        BehaviorStateMachineFixture.stateInfo(
            BehaviorStateSpec(stateId: 0, name: "Left", generator: left, transitions: transitions)
        ),
        at: 0x400
    )
    let rightState = table.add(
        BehaviorStateMachineFixture.stateInfo(
            BehaviorStateSpec(stateId: 1, name: "Right", generator: right)
        ),
        at: 0x410
    )
    let root = table.add(
        BehaviorStateMachineFixture.machine("machine", states: [leftState, rightState]),
        at: 0x500
    )
    return BehaviorFixture.instance(
        root: root,
        table: table,
        data: BehaviorFixture.graphData(events: ["go"]),
        clips: clips
    )
}

struct BehaviorClipLoadingTests {
    private static let step: Float = 0.1

    @Test func aStateWhoseClipIsLoadingKeepsTheCurrentPose() {
        let clips = LoadingClipSource(
            table: BehaviorFixture.staticClipPair(left: 3, right: 10), loading: ["right"]
        )
        let graph = twoStateGraph(clips: clips)
        #expect(graph.update(deltaTime: Self.step).bones[1].translation.x == 3)
        graph.raiseEvent(named: "go")
        let held = graph.update(deltaTime: Self.step)
        #expect(held.bones[1].translation.x == 3)
        #expect(held.rootMotion == .identity)
        #expect(graph.activeStates.map(\.stateName) == ["Right"])
        #expect(graph.tally.unresolvedClipTotal == 0)
        clips.arrive("right")
        #expect(graph.update(deltaTime: Self.step).bones[1].translation.x == 10)
    }

    @Test func buildingAGraphPrefetchesOnlyTheStartStateClips() {
        let clips = LoadingClipSource(
            table: BehaviorFixture.staticClipPair(left: 0, right: 10), loading: []
        )
        let graph = twoStateGraph(clips: clips)
        graph.prefetchReachableClips()
        #expect(clips.prefetched == ["left"])
    }

    @Test func theInstallSourceLoadsOnItsWorkerAndArrivesAtTheDrain() throws {
        let clip = try BehaviorFixture.splineClip()
        let source = InstallBehaviorClipSource(
            paths: ["meshes\\actors\\character\\animations\\walk.hkx"],
            worker: ImmediateAssetLoadWorker<String, SplineBehaviorClip> { _ in clip }
        )
        #expect(source.clip(named: "Walk.hkx", bindingIndex: -1) == nil)
        #expect(source.isLoading(named: "Walk.hkx", bindingIndex: -1))
        #expect(source.drain() == 1)
        #expect(!source.isLoading(named: "Walk.hkx", bindingIndex: -1))
        #expect(source.clip(named: "Walk.hkx", bindingIndex: -1)?.duration == clip.duration)
        #expect(source.loadedCount == 1)
    }

    @Test func aFailedInstallLoadIsAMissAndIsNotRequestedAgain() {
        let source = InstallBehaviorClipSource(
            paths: ["meshes\\actors\\character\\animations\\walk.hkx"],
            worker: ImmediateAssetLoadWorker<String, SplineBehaviorClip> { path in
                throw PlayerClipTestError.unreadable(path)
            }
        )
        _ = source.clip(named: "walk.hkx", bindingIndex: -1)
        source.drain()
        #expect(source.clip(named: "walk.hkx", bindingIndex: -1) == nil)
        #expect(!source.isLoading(named: "walk.hkx", bindingIndex: -1))
        #expect(source.missCount == 1)
    }

    @Test func aPrefetchedInstallClipIsReadyWithoutANeededRequest() throws {
        let clip = try BehaviorFixture.splineClip()
        let source = InstallBehaviorClipSource(
            paths: ["meshes\\actors\\character\\animations\\idle.hkx"],
            worker: ImmediateAssetLoadWorker<String, SplineBehaviorClip> { _ in clip }
        )
        source.prefetch(named: "idle.hkx")
        source.drain()
        #expect(source.clip(named: "idle.hkx", bindingIndex: -1) != nil)
    }

    @Test func eachGraphReadsTheAnimationFolderBesideItsBehaviors() {
        let third = InstallBehaviorClipSource.animationFolder(
            forBehaviorPath: "meshes\\actors\\character\\behaviors\\0_master.hkx"
        )
        let first = InstallBehaviorClipSource.animationFolder(
            forBehaviorPath: "meshes\\actors\\character\\_1stperson\\behaviors\\0_master.hkx"
        )
        #expect(third == InstallBehaviorClipSource.animationPrefix)
        #expect(first == "meshes\\actors\\character\\_1stperson\\animations\\")
        let archive = [
            "meshes\\actors\\character\\animations\\mt_idle.hkx",
            "meshes\\actors\\character\\_1stperson\\animations\\mt_idle.hkx"
        ]
        #expect(InstallBehaviorClipSource.clipPaths(archive, in: first) == [archive[1]])
        #expect(InstallBehaviorClipSource.clipPaths(archive, in: third) == [archive[0]])
    }
}

private enum PlayerClipTestError: Error {
    case unreadable(String)
}
