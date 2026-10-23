// Global `Game` and `Debug` natives the app answers through `PapyrusGameNatives`:
// saving, quitting, fades, screen blood, the title menu, god mode, and the grabbed
// reference. See docs/engine/papyrus-world.md#session-natives.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions {
    static func installGameSession(into registry: inout PapyrusNativeRegistry) {
        installSaveAndQuit(into: &registry)
        installScreen(into: &registry)
        installDebugSession(into: &registry)
        installPlayerSession(into: &registry)
    }

    private static func installSaveAndQuit(into registry: inout PapyrusNativeRegistry) {
        for (name, autosave) in [("RequestSave", false), ("RequestAutoSave", true)] {
            gameHook("Game", name, into: &registry) { _, hooks in
                guard let save = hooks.requestSave else { return nil }
                _ = save(autosave)
                return .returned(.none)
            }
        }
        gameHook("Game", "QuitToMainMenu", into: &registry) { _, hooks in
            hooks.quitToMainMenu.map { $0()
                return .returned(.none)
            }
        }
        gameHook("Debug", "QuitGame", into: &registry) { _, hooks in
            hooks.quitGame.map { $0()
                return .returned(.none)
            }
        }
    }

    private static func installScreen(into registry: inout PapyrusNativeRegistry) {
        // `FadeOutGame(bool abFadingOut, bool abBlackFade, float afSecsBeforeFade,
        // float afFadeDuration)` (<https://ck.uesp.net/wiki/FadeOutGame_-_Game>).
        gameHook("Game", "FadeOutGame", into: &registry) { call, hooks in
            guard let fade = hooks.fade else { return nil }
            fade(PapyrusFade(
                fadingOut: boolean(call, at: 0, default: true),
                black: boolean(call, at: 1, default: true),
                delay: max(0, float(call, at: 2) ?? 0),
                duration: max(0, float(call, at: 3) ?? 0)
            ))
            return .returned(.none)
        }
        gameHook("Game", "TriggerScreenBlood", into: &registry) { call, hooks in
            guard let blood = hooks.screenBlood else { return nil }
            blood(Int(max(0, integer(call, at: 0) ?? 0)))
            return .returned(.none)
        }
        gameHook("Game", "ClearTempEffects", into: &registry) { _, hooks in
            hooks.clearTempEffects.map { $0()
                return .returned(.none)
            }
        }
        for (name, shown) in [("ShowTitleSequenceMenu", true), ("HideTitleSequenceMenu", false)] {
            gameHook("Game", name, into: &registry) { _, hooks in
                hooks.showTitleSequenceMenu.map { $0(shown)
                    return .returned(.none)
                }
            }
        }
        gameHook("Game", "ShowFirstPersonGeometry", into: &registry) { call, hooks in
            guard let show = hooks.showFirstPersonGeometry else { return nil }
            show(boolean(call, at: 0, default: true))
            return .returned(.none)
        }
    }

    private static func installDebugSession(into registry: inout PapyrusNativeRegistry) {
        gameHook("Debug", "TakeScreenshot", into: &registry) { call, hooks in
            guard let capture = hooks.takeScreenshot else { return nil }
            _ = capture(string(call, at: 0) ?? "")
            return .returned(.none)
        }
        gameHook("Debug", "ToggleCollisions", into: &registry) { _, hooks in
            hooks.toggleCollisions.map { $0()
                return .returned(.none)
            }
        }
        gameHook("Debug", "SetGodMode", into: &registry) { call, hooks in
            guard let setGodMode = hooks.setGodMode else { return nil }
            setGodMode(boolean(call, at: 0, default: true))
            return .returned(.none)
        }
        // "Moves the player to the cell and waits for it to load."
        gameHook("Debug", "CenterOnCellAndWait", into: &registry) { call, hooks in
            guard let center = hooks.centerOnCell else { return nil }
            guard let cell = string(call, at: 0), center(cell) else {
                return failure(call, "CenterOnCellAndWait found no such cell")
            }
            return .returned(.none)
        }
        // A link to Bethesda's debug server; nothing listens, as in a retail game.
        registry.register(PapyrusNativeFunction(
            scriptName: "Debug", functionName: "DBSendPlayerPosition"
        ) { _, _ in .returned(.none) })
    }

    private static func installPlayerSession(into registry: inout PapyrusNativeRegistry) {
        gameHook("Game", "ClearPrison", into: &registry) { _, hooks in
            hooks.clearPrison.map { $0()
                return .returned(.none)
            }
        }
        gameHook("Game", "SetPlayerReportCrime", into: &registry) { call, hooks in
            guard let set = hooks.setPlayerReportsCrime else { return nil }
            set(boolean(call, at: 0, default: true))
            return .returned(.none)
        }
        registry.register(PapyrusNativeFunction(
            scriptName: "Game", functionName: "GetPlayerGrabbedRef"
        ) { call, context in
            guard let bridge = context.world as? PapyrusWorldStateBridge else {
                return needsWorld(call)
            }
            let grabbed = bridge.gameNatives.playerGrabbedReference?()
            return .returned(grabbed.flatMap(bridge.objectHandle(for:))
                .map { .object($0) } ?? .none)
        })
    }

    /// Registers a global native whose `body` uses the app's hooks. A nil answer means
    /// the hook is missing, which fails the call with a reason.
    static func gameHook(
        _ script: String, _ name: String,
        into registry: inout PapyrusNativeRegistry,
        body: @escaping @MainActor (PapyrusNativeCall, PapyrusGameNatives) -> PapyrusNativeResult?
    ) {
        registry
            .register(PapyrusNativeFunction(
                scriptName: script,
                functionName: name
            ) { call, context in
                guard let bridge = context.world as? PapyrusWorldStateBridge else {
                    return needsWorld(call)
                }
                return body(call, bridge.gameNatives)
                    ?? failure(call, "\(call.qualifiedName) needs the running game")
            })
    }
}
