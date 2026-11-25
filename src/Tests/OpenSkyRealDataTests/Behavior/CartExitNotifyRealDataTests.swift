// The cart exit idles reach a state of `0_master.hkx` that sends `ExitCartEnd` as it
// ends, and plays its clip once. The seat idles loop, so a rider stays seated.
// Names only.

import Foundation
@testable import OpenSkyBehavior
@testable import OpenSkyFormatsAnimation
@testable import OpenSkyGameData
import Testing

struct CartExitNotifyRealDataTests {
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func theCartExitStatesSendExitCartEnd() throws {
        let index = try Self.masterIndex()
        // The carriage quest fills its player and passenger exits with the prisoner
        // idles, then waits for `ExitCartEnd`; it never calls `SetVehicle(None)` on them.
        let events = [
            "IdleCartDriverExit", "IdleCartPrisonerAExit", "IdleCartPrisonerBExit",
            "IdleCartPrisonerCExit", "IdleCartPrisonerDExit"
        ]
        for event in events {
            let clip = try #require(
                index.clip(forEvent: event, behaviorFile: "0_master.hkx"),
                "\(event)"
            )
            #expect(clip.notify.enter.contains("ExitCartBegin"), "\(event)")
            #expect(clip.notify.exit == ["ExitCartEnd"], "\(event)")
            #expect(!clip.loops, "\(event)")
        }
    }

    /// Each exit clip's trigger near its end is the event that takes the graph out of the
    /// cart state, read from the graph's transitions (docs/engine/vehicles.md).
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func eachExitClipLeavesOnItsTrigger() throws {
        let index = try Self.masterIndex()
        let expected = [
            "IdleCartPrisonerAExit": "OffsetBoundStandingStart",
            "IdleCartPrisonerBExit": "OffsetBoundStandingCartStart",
            "IdleCartPrisonerCExit": "OffsetBoundStandingCartStart",
            "IdleCartPrisonerDExit": "OffsetBoundStandingCartStart",
            "IdleCartDriverExit": "CartExit"
        ]
        for (event, trigger) in expected {
            let clip = try #require(
                index.clip(forEvent: event, behaviorFile: "0_master.hkx"),
                "\(event)"
            )
            #expect(clip.leavingTriggers.map(\.name) == [trigger], "\(event)")
        }
    }

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func theCartSeatStatesLoop() throws {
        let index = try Self.masterIndex()
        for event in ["IdleCartPrisonerAIdle", "IdleCartPrisonerCIdle", "IdleCartDriverIdle"] {
            let clip = try #require(
                index.clip(forEvent: event, behaviorFile: "0_master.hkx"),
                "\(event)"
            )
            #expect(clip.loops, "\(event)")
        }
    }

    private static func masterIndex() throws -> BehaviorEventClipIndex {
        let root = try #require(RealDataEnvironment.dataRoot)
        let vfs = VirtualFileSystem(root: root)
        return BehaviorEventClipIndex { name in
            guard
                let data = try? vfs
                    .contents(forPath: "meshes\\actors\\character\\behaviors\\" + name),
                let file = try? HKXFile(data: data)
            else { return nil }
            return try? HKXObjectGraph(file: file)
        }
    }
}
