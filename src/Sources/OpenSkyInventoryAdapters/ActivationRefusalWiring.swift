// `ActivationRefusalWorldAdapter` joins the started session: what `wire` registered.

import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCombatInterface
import OpenSkyDialogueInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// Connects `ActivationRefusalWorldAdapter` to the started session.
public struct ActivationRefusalWiring {
    public init(_ adapter: ActivationRefusalWorldAdapter) {
        guard let streamer = adapter.game.streamer else { return }
        streamer.activationGate.register(.notice) { [weak adapter] target in
            guard let adapter else { return nil }
            let texts = adapter.game.mapWorld.settingTexts(ActivationRefusalText.self)
            return ActivationRefusalRule.refusal(adapter.facts(for: target), texts: texts).map {
                .notice($0)
            }
        }
        streamer.activationGate.refusals.register(.notice) { [weak adapter] event in
            guard let adapter, case let .notice(text) = event.refusal else { return }
            adapter.game.hud.showNotification(text)
        }
    }
}
