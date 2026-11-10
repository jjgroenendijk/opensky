import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyFactionsInterface
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPerceptionInterface
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `InventoryPickpocketAdapter` reads from the session.
@MainActor
public protocol InventoryPickpocketHost: AnyObject, SendableMetatype {
    var actorValues: any ActorValuePort { get }
    var actorWorld: any ActorWorldPort { get }
    var magic: any MagicPort { get }
    var perception: any PerceptionPort { get }
    var scripts: any ScriptPort { get }
    var worldState: any WorldStateStorePort { get }
}

/// Part of `InventoryWorldAdapter`, over its own narrow host.
public struct InventoryPickpocketAdapter {
    public let game: any InventoryPickpocketHost
}

extension InventoryPickpocketAdapter {
    public func pickpocketCaughtDay(of key: ReferenceKey) -> Float? {
        game.scripts.bridge?.scriptedState(of: key).value(ScriptedStateName.pickpocketCaughtDay)
    }

    public func notePickpocketCatch(
        on day: Float?,
        chargedTo faction: ReferenceKey?,
        by key: ReferenceKey
    ) {
        game.scripts.bridge?.updateScriptedState(of: key) {
            $0.setValue(ScriptedStateName.pickpocketCaughtDay, day)
            $0.setForm(ScriptedStateName.pickpocketCaughtFaction, faction)
        }
    }

    public func forgetPickpocketCatch(of key: ReferenceKey) {
        game.scripts.bridge?.updateScriptedState(of: key) {
            $0.setValue(ScriptedStateName.pickpocketCaughtDay, nil)
            $0.setForm(ScriptedStateName.pickpocketCaughtFaction, nil)
        }
    }

    /// Unlinks every catch charged to `faction`; `forgotten` also ends its refusal.
    public func settlePickpocketCatches(chargedTo faction: ReferenceKey, forgotten: Bool) {
        let name = ScriptedStateName.pickpocketCaughtFaction
        for key in game.worldState.sortedDirtyKeys() {
            guard
                game.worldState.component(ScriptedReferenceState.self, for: key)?.form(name)
                == faction
            else { continue }
            if forgotten {
                forgetPickpocketCatch(of: key)
            } else {
                game.scripts.bridge?.updateScriptedState(of: key) { $0.setForm(name, nil) }
            }
        }
    }

    public func actorValue(_ index: Int32, of key: ReferenceKey) -> Float? {
        guard
            let runtime = game.actorValues.runtime,
            let holder = key == .player ? .player : game.actorWorld.actorValueHolder(for: key)
        else { return nil }
        return runtime.value(at: index, on: holder)
    }

    public func detectsPlayer(_ observer: ReferenceKey) -> Bool {
        game.perception.runtime?.state(observer: observer, target: .player).state == .detected
    }

    public func applyPlacedPoison(_ poison: FormID, on target: ReferenceKey) -> Bool {
        game.magic.applyPlacedPoison(poison, by: .player, on: target) != nil
    }
}
