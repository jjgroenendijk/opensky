// The `Game` family (issue #172), which is one function so far.
//
// `Game` is where the vanilla script corpus reaches for anything session-wide,
// and almost all of it — quests, the menu stack, the camera, difficulty — has
// no engine behind it yet. Only `GetPlayer` is installed, because it is the
// one call that can be answered honestly today and the one every other family
// needs: it is how a script names the activator it was handed.

import Foundation

nonisolated extension PapyrusNativeFunctions {
    /// `Actor GetPlayer()` — a global function, so it arrives with no receiver.
    ///
    /// The player has no plugin record in this engine and no script instance,
    /// so the handle is the opaque one `PapyrusWorldRuntime` mints for
    /// `ReferenceKey.player` and caches for the session. Two calls therefore
    /// return the same handle, and comparing it against an `akActionRef` in
    /// script code answers "did the player do this?" correctly.
    ///
    /// The returned handle names the player but resolves to no `Actor` script,
    /// so an `Actor`-only method called on it dispatches as an unimplemented
    /// native and is tallied — visibly missing rather than silently wrong.
    static func installGame(into registry: inout PapyrusNativeRegistry) {
        registry.register(PapyrusNativeFunction(
            scriptName: "Game",
            functionName: "GetPlayer"
        ) { call, context in
            guard
                let world = context.world,
                let handle = world.objectHandle(for: world.playerKey)
            else {
                return failure(call, "GetPlayer needs a world runtime")
            }
            return .returned(.object(handle))
        })
    }
}
