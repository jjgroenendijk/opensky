// `Actor` natives over game rules: deferred kills, feeding, combat spells, paired idles,
// owned doors, ash piles, and the knock-back of `KnockAreaEffect`. Signatures are from
// <https://ck.uesp.net/wiki/Actor_Script>. See docs/engine/papyrus-world.md.

import Foundation
import OpenSkyCrimeInterface
import OpenSkyFormatsESM
import OpenSkyInventoryInterface
import OpenSkyScriptingInterface
import OpenSkyWorldInterface
import OpenSkyWorldState

extension PapyrusNativeFunctions {
    /// `KnockAreaEffect` magnitude 1 to speed, in units per second. [WARNING] OpenSky's
    /// reading: no open source gives the game's scale.
    static let knockAreaSpeed: Float = 1000

    static func installActorRules(into registry: inout PapyrusNativeRegistry) {
        installDeferredKill(into: &registry)
        installFeeding(into: &registry)
        installActorActions(into: &registry)
        installOwnedDoors(into: &registry)
        installKnockAreaEffect(into: &registry)
    }

    /// While a kill is deferred, zero health does not kill. Ending it lets the next
    /// death sweep kill an actor that is still at zero
    /// (<https://ck.uesp.net/wiki/EndDeferredKill_-_Actor>).
    private static func installDeferredKill(into registry: inout PapyrusNativeRegistry) {
        for (name, deferred) in [("StartDeferredKill", true), ("EndDeferredKill", false)] {
            scriptState("Actor", name, into: &registry) { _, bridge, key in
                bridge.updateScriptedState(of: key) {
                    $0.setFlag(ScriptedStateName.deferredKill, deferred ? true : nil)
                }
                return .returned(.none)
            }
        }
        // OpenSky plays no kill moves.
        scriptState("Actor", "IsInKillMove", into: &registry) { _, _, _ in
            .returned(.boolean(false))
        }
    }

    private static func installFeeding(into registry: inout PapyrusNativeRegistry) {
        // The feeding animation is not played; the event and its effects are.
        scriptState("Actor", "StartVampireFeed", into: &registry) { call, bridge, key in
            guard let target = objectArgument(call, at: 0).flatMap(bridge.referenceKey(for:))
            else { return failure(call, "StartVampireFeed needs a target") }
            bridge.world?.queueVampireFeed(feeder: key, target: target)
            return .returned(.none)
        }
        scriptState("Actor", "StartCannibal", into: &registry) { call, bridge, _ in
            guard let target = objectArgument(call, at: 0).flatMap(bridge.referenceKey(for:))
            else { return failure(call, "StartCannibal needs a target") }
            bridge.updateScriptedState(of: target) { $0.setFlag(ScriptedStateName.eaten, true) }
            return .returned(.none)
        }
    }

    private static func installActorActions(into registry: inout PapyrusNativeRegistry) {
        // `DoCombatSpellApply(Spell akSpell, ObjectReference akTarget)`: the spell lands
        // on the target as this actor's cast, so resistances and hit events apply.
        scriptState("Actor", "DoCombatSpellApply", into: &registry) { call, bridge, key in
            guard
                let spell = objectArgument(call, at: 0).flatMap(bridge.referenceKey(for:)),
                let target = objectArgument(call, at: 1).flatMap(bridge.referenceKey(for:))
            else { return failure(call, "DoCombatSpellApply needs a spell and a target") }
            guard bridge.castSpell(spell, from: key, at: target) else {
                return failure(call, "DoCombatSpellApply has no caster runtime or no such spell")
            }
            return .returned(.none)
        }
        // The idle plays; OpenSky has no paired animations, so the target is not moved.
        scriptState("Actor", "PlayIdleWithTarget", into: &registry) { call, bridge, key in
            guard
                let ai = bridge.actorAI,
                case let .plugin(plugin, objectID)? = objectArgument(call, at: 0)
                    .flatMap(bridge.referenceKey(for:))
            else { return failure(call, "PlayIdleWithTarget needs an idle and the actor AI") }
            let idle = ResolvedFormID(plugin: plugin, objectID: objectID)
            return .returned(.boolean(ai.playIdle(idle, on: key)))
        }
        scriptState("Actor", "ClearArrested", into: &registry) { _, bridge, key in
            bridge.updateScriptedState(of: key) {
                $0.setFlag("resistingArrest", nil)
                $0.setFlag("arrested", nil)
            }
            return .returned(.none)
        }
        scriptState("Actor", "MoveToPackageLocation", into: &registry) { call, bridge, key in
            guard let point = bridge.gameNatives.packageLocation?(key) else {
                return failure(call, "MoveToPackageLocation found no package location")
            }
            bridge.move(key, to: point)
            return .returned(.none)
        }
        scriptState("Actor", "ClearExtraArrows", into: &registry) { call, bridge, key in
            guard let clear = bridge.gameNatives.clearExtraArrows else {
                return failure(call, "ClearExtraArrows needs the running game")
            }
            _ = clear(key)
            return .returned(.none)
        }
        installAshPile(into: &registry)
    }

    /// `AttachAshPile(Form akAshPileBase = None)`: the pile is placed at the actor's feet,
    /// and each links to the other, so activating the pile activates the actor.
    private static func installAshPile(into registry: inout PapyrusNativeRegistry) {
        scriptState("Actor", "AttachAshPile", into: &registry) { call, bridge, key in
            let base = objectArgument(call, at: 0).flatMap(bridge.referenceKey(for:))
                ?? defaultAshPile
            guard let pile = bridge.trapWorld?.placeAtMe(base, at: key, count: 1) else {
                return failure(call, "AttachAshPile could not place the pile")
            }
            bridge.updateScriptedState(of: key) { $0.setForm(ashPileName, pile) }
            bridge.updateScriptedState(of: pile) { $0.setForm(ashPileOwnerName, key) }
            return .returned(.none)
        }
    }

    static let ashPileName = "ashPile"
    static let ashPileOwnerName = "ashPileOwner"
    /// `DefaultAshPile1`. Its ID is below 0x800, the range the engine itself names.
    static let defaultAshPile = ReferenceKey.plugin(name: "Skyrim.esm", objectID: 0x1B)

    /// "This actor unlocks all teleport doors he owns in his current parent cell."
    private static func installOwnedDoors(into registry: inout PapyrusNativeRegistry) {
        scriptState("Actor", "UnLockOwnedDoorsInCell", into: &registry) { _, bridge, key in
            let cell = bridge.cellLocation(of: key)
            let base = bridge.resolvedBase(of: key)
            for entry in bridge.references?.residentEntries() ?? [] {
                guard
                    let placed = entry.placedReference, placed.teleportDestination != nil,
                    bridge.cellLocation(of: entry.key) == cell,
                    owner(of: entry.key, placed, bridge) == base,
                    var lock = bridge.lockState(for: entry.key), lock.isLocked
                else { continue }
                lock.isLocked = false
                bridge.write(lock.erased, for: entry.key)
            }
            return .returned(.none)
        }
    }

    private static func owner(
        of key: ReferenceKey, _ placed: PlacedReference, _ bridge: PapyrusWorldStateBridge
    ) -> ReferenceKey? {
        if let scripted = bridge.scriptedOwner(of: key) {
            guard case let .actor(actor)? = scripted else { return nil }
            return actor
        }
        return placed.owner.flatMap(bridge.referenceKey(forFormID:))
    }

    /// `KnockAreaEffect(float afMagnitude, float afRadius)`: every actor within the
    /// radius but the receiver is pushed away from it.
    private static func installKnockAreaEffect(into registry: inout PapyrusNativeRegistry) {
        scriptState("ObjectReference", "KnockAreaEffect", into: &registry) { call, bridge, key in
            guard
                let magnitude = float(call, at: 0), magnitude.isFinite,
                let radius = float(call, at: 1), radius.isFinite,
                let centre = position(of: key, bridge)
            else { return failure(call, "KnockAreaEffect needs a magnitude and a radius") }
            guard let trapWorld = bridge.trapWorld else { return .deviated(.none, .stubbed) }
            let speed = min(max(magnitude, 0), 1) * knockAreaSpeed
            let actors = findCandidates(
                bridge, filter: .actors, bases: [], around: centre, radius: radius
            )
            for actor in actors.map(\.key).sorted() where actor != key {
                _ = trapWorld.pushActor(actor, awayFrom: key, along: nil, speed: speed)
            }
            return .returned(.none)
        }
    }
}
