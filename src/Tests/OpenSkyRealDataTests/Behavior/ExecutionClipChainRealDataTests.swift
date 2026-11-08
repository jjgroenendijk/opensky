// The chopping block's machines in `mt_behavior.hkx`: a furniture idle enters each
// role's machine at its start state and follows the enter clip's `ExecutionNextClip`
// to the idle loop. From there one chop event leads each role to its own clip, and the
// executioner's clips draw the axe prop.

import Foundation
@testable import OpenSkyActorPresentation
@testable import OpenSkyBehavior
@testable import OpenSkyFormatsAnimation
import OpenSkyFormatsESM
@testable import OpenSkyGameData
import Testing

struct ExecutionClipChainRealDataTests {
    private static let master = "Actors\\Character\\Behaviors\\0_Master.hkx"

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func eachRoleEntersItsMachineAndHoldsItsIdle() throws {
        let index = try Self.index()
        let roles = [
            ("IdleExecutioneeIdle", "aoexecutioneeenter", "aoexecutioneeidle"),
            ("IdleExecutionerIdle", "aoexecutionerenter", "aoexecutioneridle")
        ]
        for (event, enter, idle) in roles {
            let clip = try #require(index.clip(forEvent: event, behaviorFile: Self.master))
            #expect(clip.animationName.lowercased().contains(enter), "\(event)")
            #expect(!clip.loops, "\(event)")
            let last = try #require(clip.followUps.last, "\(event)")
            #expect(last.animationName.lowercased().contains(idle), "\(event)")
            #expect(last.loops, "\(event)")
            #expect(clip.position != nil, "\(event)")
        }
    }

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func theChopEventLeadsEachRoleToItsOwnClip() throws {
        let index = try Self.index()
        let roles = [
            ("IdleExecutioneeIdle", "aoexecutioneechop"),
            ("IdleExecutionerIdle", "aoexecutionerchop")
        ]
        for (seat, chop) in roles {
            let seated = try #require(index.clip(forEvent: seat, behaviorFile: Self.master))
            let clip = try #require(index.clip(
                forEvent: "IdleExecutionerChop", behaviorFile: Self.master, from: seated.position
            ))
            #expect(clip.animationName.lowercased().contains(chop), "\(seat)")
        }
        let prisoner = try #require(index.clip(
            forEvent: "IdleExecutionerChop", behaviorFile: Self.master,
            from: index.clip(forEvent: "IdleExecutioneeIdle", behaviorFile: Self.master)?.position
        ))
        let names = prisoner.triggers.map(\.name)
        #expect(names.contains("Decapitate"))
        #expect(names.contains("KillActor"))
    }

    /// The headsman's axe is no item: the executioner's clips draw the
    /// `AnimObjectExecutionerAxe` prop, which rides the bone its mesh names.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func theExecutionerIdleDrawsTheAxeProp() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let store = IdleStore(plugins: ActivePluginFiles.load(root: root))
        let resolver = IdlePlaybackResolver(
            files: VirtualFileSystem(root: root), animatedObjects: store.animatedObjects
        )
        let names: Set = ["IdleExecutionerEnterInstant", "IdleExecutionerIdle"]
        let plans = store.idles.records
            .filter { names.contains($0.record.editorID ?? "") }
            .map { resolver.plan(for: store.inheritingBehaviorFile($0)) }
        try #require(plans.count == names.count)
        let props = plans.flatMap { $0.animationObjects.map(\.prop) + [$0.prop] }
        let axe = props.first {
            if case let .attached(editorID, _, _) = $0 {
                return editorID == "AnimObjectExecutionerAxe"
            }
            return false
        }
        #expect(axe != nil, "\(plans)")
    }

    private static func index() throws -> BehaviorEventClipIndex {
        let root = try #require(RealDataEnvironment.dataRoot)
        let vfs = VirtualFileSystem(root: root)
        return BehaviorEventClipIndex { name in
            guard
                let path = IdlePlaybackResolver.behaviorPath(
                    name, project: "meshes\\actors\\character\\"
                ),
                let data = try? vfs.contents(forPath: path),
                let file = try? HKXFile(data: data)
            else { return nil }
            return try? HKXObjectGraph(file: file)
        }
    }
}
