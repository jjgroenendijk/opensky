// `Actor.ShowBarterMenu` (issue #506, roadmap item 21.7): the native the load
// order's merchant dialogue calls to open trade. On the local install 32 of the
// 39 scripted INFOs conditioned on `JobMerchantFaction` run a fragment that
// calls it on the speaker, so implementing it is what puts barter behind the
// vanilla dialogue rather than behind a separate control.
//
// "Shows the barter menu for this actor." — `Function ShowBarterMenu()
// native` (<https://ck.uesp.net/wiki/ShowBarterMenu_-_Actor>). The page notes
// that the original shows an empty menu for an actor that is not loaded or
// whose merchant conditions fail; this engine refuses instead and says why,
// because an empty shop reads as a vendor with nothing to sell.
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
