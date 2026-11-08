// `TraceUser` writes only to a log `OpenUserLog` opened, and `ToggleMenus` reaches the HUD.

import Foundation
@testable import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyWorldState
import Testing

@MainActor
struct PapyrusNativeDebugTests {
    private static func debug(
        _ name: String,
        _ arguments: [PapyrusValue] = []
    ) -> PapyrusNativeCall {
        PapyrusNativeCall(
            kind: .staticFunction, scriptName: "Debug", functionName: name, receiver: nil,
            arguments: arguments, returnType: .boolean
        )
    }

    @Test func traceUserWritesOnlyToAnOpenLog() {
        let context = PapyrusNativeContext()
        var registry = PapyrusNativeRegistry(context: context)
        PapyrusNativeFunctions.installDebug(into: &registry)
        let trace = Self.debug("TraceUser", [.string("quests"), .string("stage 10")])
        #expect(registry.invoke(trace) == .returned(.boolean(false)))
        let open = Self.debug("OpenUserLog", [.string("quests")])
        #expect(registry.invoke(open) == .returned(.boolean(true)))
        #expect(registry.invoke(open) == .returned(.boolean(false)))
        #expect(registry.invoke(trace) == .returned(.boolean(true)))
        #expect(context.log.messages.last == "quests: stage 10")
        _ = registry.invoke(Self.debug("CloseUserLog", [.string("quests")]))
        #expect(registry.invoke(trace) == .returned(.boolean(false)))
    }

    @Test func toggleMenusNeedsTheHUD() {
        let bridge = PapyrusWorldStateBridge(worldState: WorldStateStore())
        var registry = PapyrusNativeRegistry(context: PapyrusNativeContext(world: bridge))
        PapyrusNativeFunctions.installDebug(into: &registry)
        guard case .failed = registry.invoke(Self.debug("ToggleMenus")) else {
            Issue.record("ToggleMenus answered without the HUD")
            return
        }
        var toggles = 0
        bridge.playerNatives.toggleMenus = { toggles += 1 }
        #expect(registry.invoke(Self.debug("ToggleMenus")) == .returned(.none))
        #expect(toggles == 1)
    }
}
