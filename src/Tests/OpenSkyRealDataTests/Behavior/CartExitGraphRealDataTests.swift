// The cart exit on the real install: a prisoner's exit clip raises the arm event near its
// end, and that event takes the live graph out of the cart state. Asserts on state and
// event names only. See docs/engine/vehicles.md#how-an-exit-state-ends.

import Foundation
@testable import OpenSkyActorPresentation
@testable import OpenSkyBehavior
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import OpenSkyWorldInterface
import Testing

struct CartExitGraphRealDataTests {
    private static let timestep: Float = 1.0 / 30.0

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func aPrisonersExitClipLeavesTheCartState() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let loadOrder = try ActiveLoadOrder.open(root: root).plugins
        var skipped = SkippedRecords()
        let races = loadOrder.decodeRecords(of: "RACE", skipped: &skipped) {
            try Race(record: $0, localized: $1)
        }
        let files = VirtualFileSystem(root: root)
        let race = try #require(races.last { $0.editorID == "NordRace" })
        let model = try #require(race.details.behaviorGraphs.male)
        let asset = try BehaviorProjectAsset.load(
            fileSystem: files, projectPath: ActorGraphCore.projectPath(modelPath: model.path),
            folderClips: true
        )
        let instance = BehaviorGraphInstance(
            graph: asset.behavior, in: asset.objectGraph,
            skeleton: BehaviorSkeleton(asset.skeleton),
            clips: InstallBehaviorClipSource(
                fileSystem: files, paths: asset.clipPaths, projectFolder: asset.projectFolder
            )
        )
        instance.references = InstallBehaviorReferenceSource(
            fileSystem: files,
            pathsByName: InstallBehaviorReferenceSource.index(files, rootPath: asset.behaviorPath)
        )
        instance.activate()
        step(instance, seconds: 0.5)

        #expect(instance.raiseEvent(named: "IdleCartPrisonerCIdle"))
        step(instance, seconds: 1)
        #expect(states(instance).contains("Cart_State"), "\(states(instance))")

        #expect(instance.raiseEvent(named: "IdleCartPrisonerCExit"))
        // The clip is 15.67 s long and raises its arm event 0.2 s before the end.
        let fired = step(instance, seconds: 15)
        #expect(states(instance).contains("Cart_State"), "left early: \(states(instance))")
        #expect(!fired.contains("ExitCartEnd"))
        let last = step(instance, seconds: 1.5)
        #expect(last.contains("OffsetBoundStandingCartStart"), "fired: \(last.sorted())")
        #expect(last.contains("ExitCartEnd"), "fired: \(last.sorted())")
        #expect(!states(instance).contains("Cart_State"), "\(states(instance))")
    }

    @discardableResult
    private func step(_ instance: BehaviorGraphInstance, seconds: Float) -> Set<String> {
        var fired: Set<String> = []
        for _ in 0 ..< Int((seconds / Self.timestep).rounded()) {
            let update = instance.update(deltaTime: Self.timestep)
            fired.formUnion(update.firedEvents.compactMap(\.name))
        }
        return fired
    }

    private func states(_ instance: BehaviorGraphInstance) -> [String] {
        instance.activeStates.prefix(8).compactMap(\.stateName)
    }
}
