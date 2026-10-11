// The chopping block's machines in `mt_behavior.hkx`: a furniture idle enters each
// role's machine at its start state and follows the enter clip's `ExecutionNextClip`
// to the idle loop. From there one chop event leads each role to its own clip.
// Names only.

import Foundation
@testable import OpenSkyBehavior
@testable import OpenSkyFormatsAnimation
@testable import OpenSkyGameData
@testable import OpenSkyWorld
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
