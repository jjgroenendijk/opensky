// `Actor.ShowBarterMenu` (<https://ck.uesp.net/wiki/ShowBarterMenu_-_Actor>), which
// merchant dialogue fragments call to open trade. Where the game shows an empty
// menu, this engine refuses with a reason, because an empty shop looks like a
// vendor with nothing to sell.
//
// Documented in docs/engine/vendor-factions.md and docs/engine/papyrus-activation.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

/// The barter operation a Papyrus native may perform.
@MainActor
public protocol PapyrusWorldBarterBridge {
    /// Opens the barter menu against `actor`'s vendor stock, or nil for a
    /// session with no vendor data.
    func showBarterMenu(for actor: ReferenceKey) -> (opened: Bool, text: String)?
}

extension PapyrusWorldStateBridge {
    public func showBarterMenu(for actor: ReferenceKey) -> (opened: Bool, text: String)? {
        guard let showBarterMenu else { return nil }
        return showBarterMenu(actor)
    }
}

extension PapyrusNativeFunctions {
    public static func installBarter(into registry: inout PapyrusNativeRegistry) {
        registry.register(PapyrusNativeFunction(
            scriptName: "Actor",
            functionName: "ShowBarterMenu"
        ) { call, context in
            guard let actor = actorTarget(call, context) else { return needsActor(call) }
            guard let result = actor.world.showBarterMenu(for: actor.key) else {
                return failure(call, "ShowBarterMenu needs a session with vendor data")
            }
            guard result.opened else {
                return failure(call, "ShowBarterMenu: \(result.text)")
            }
            return .returned(.none)
        })
    }
}
