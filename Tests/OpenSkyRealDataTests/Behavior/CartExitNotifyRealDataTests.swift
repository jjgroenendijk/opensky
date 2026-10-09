// The cart exit idles reach a state of `0_master.hkx` that sends `ExitCartEnd` as it
// ends. `MQ101` waits for that event before it unloads a cart. Names only.

import Foundation
@testable import OpenSkyBehavior
@testable import OpenSkyFormatsAnimation
@testable import OpenSkyGameData
import Testing

struct CartExitNotifyRealDataTests {
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func theCartExitStatesSendExitCartEnd() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let vfs = VirtualFileSystem(root: root)
        let index = BehaviorEventClipIndex { name in
            guard
                let data = try? vfs
                    .contents(forPath: "meshes\\actors\\character\\behaviors\\" + name),
                let file = try? HKXFile(data: data)
            else { return nil }
            return try? HKXObjectGraph(file: file)
        }
        for event in ["IdleCartDriverExit", "IdleCartPrisonerAExit", "IdleCartPrisonerCExit"] {
            let clip = try #require(
                index.clip(forEvent: event, behaviorFile: "0_master.hkx"),
                "\(event)"
            )
            #expect(clip.notify.enter.contains("ExitCartBegin"), "\(event)")
            #expect(clip.notify.exit == ["ExitCartEnd"], "\(event)")
        }
    }
}
