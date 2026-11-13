// Activation: the record, the `OnActivate` events, and the `XAPR` children.

import Foundation
import OpenSkyActorsInterface
import OpenSkyDialogueInterface
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyQuestsInterface
public import OpenSkyScriptingInterface
public import OpenSkyWorldInterface
public import OpenSkyWorldState

extension PapyrusWorldStateBridge.Activations {
    /// Stores a component the VM holds. A spawn uses its own cell; quests, aliases and
    /// dialogue have none; placed state uses the reference's cell. Gameplay natives use
    /// their runtimes instead. Spellbook, enchantment, perk, faction, progress and
    /// crime kinds are refused. A transform write ends a scripted move.
    @discardableResult
    public func write(
        _ component: WorldStateComponentValue, for key: ReferenceKey
    ) -> Bool {
        switch component.kind {
        case .spawn:
            guard let spawn = component.value(as: ReferenceSpawnState.self) else { return false }
            return bridge.worldState.set(spawn, for: key, in: spawn.location)
        case .quest, .questAliases, .dialogue:
            return bridge.worldState.set(component.base, for: key)
        case .transform:
            bridge.scriptedMoves.endTranslation(of: key)
            return bridge.worldState.set(component.base, for: key, in: bridge.cellLocation(of: key))
        case .enableState, .activation, .deletion, .inventory,
             .actorValues, .death, .combat, .activeEffects, .lock:
            return bridge.worldState.set(component.base, for: key, in: bridge.cellLocation(of: key))
        default:
            return false
        }
    }

    /// The actor an `AttachAshPile` pile stands for; nil for anything else.
    public func ashPileOwner(of key: ReferenceKey) -> ReferenceKey? {
        bridge.scriptState.scriptedState(of: key).form(PapyrusWorldStateBridge.ashPileOwnerName)
    }

    /// Records one activation, queues `OnActivate` on the target's scripts, and
    /// passes it to the target's `XAPR` activate children, each activated by its
    /// parent. A child with a delay waits for `advanceDelayedActivations`. Each
    /// reference is activated at most once per call, so a cycle ends.
    @discardableResult
    public func activate(
        _ target: ReferenceKey,
        by activator: ReferenceKey,
        togglesOpen: Bool
    ) -> PapyrusActivationOutcome {
        let outcome = activateOne(target, by: activator, togglesOpen: togglesOpen)
        guard !outcome.cappedByRecursion else { return outcome }
        var queuedEvents = outcome.queuedEvents
        var visited: Set = [target]
        if let actor = ashPileOwner(of: target), visited.insert(actor).inserted {
            queuedEvents += activateOne(actor, by: activator, togglesOpen: false).queuedEvents
        }
        var parents = [target]
        while let parent = parents.popLast() {
            for child in bridge.ports.references?.activateChildren(of: parent) ?? []
                where visited.insert(child.key).inserted
            {
                guard child.delay <= 0 else {
                    bridge.runState.delayedActivations.append(DelayedActivation(
                        child: child.key, parent: parent, remaining: child.delay
                    ))
                    continue
                }
                queuedEvents += activateOne(child.key, by: parent, togglesOpen: false)
                    .queuedEvents
                parents.append(child.key)
            }
        }
        return PapyrusActivationOutcome(
            recorded: outcome.recorded, queuedEvents: queuedEvents, cappedByRecursion: false
        )
    }

    /// The recursion cap is consulted first: a refused activation writes no
    /// state either, so a script pair activating each other cannot keep
    /// incrementing `activationCount` forever.
    func activateOne(
        _ target: ReferenceKey,
        by activator: ReferenceKey,
        togglesOpen: Bool
    ) -> PapyrusActivationOutcome {
        let queued = bridge.world?.queueOnActivate(target: target, activator: activator)
            ?? .none
        guard !queued.cappedByRecursion else { return queued }
        let current = bridge.worldState.component(ReferenceActivationState.self, for: target)
            ?? bridge.referenceState(for: target)?.activation
            ?? .untouched
        let recorded = write(
            current.activated(
                by: activator,
                togglesOpen: togglesOpen && !bridge.scriptState.isActivationBlocked(target)
            )
            .erased,
            for: target
        )
        return PapyrusActivationOutcome(
            recorded: recorded,
            queuedEvents: queued.queuedEvents,
            cappedByRecursion: false
        )
    }

    /// `CellStreamer.onInteraction` subscriber: records one activation and queues one
    /// `OnActivate` per script. An unknown reference is dropped. A door-style `open` sets
    /// `togglesOpen`, which drives `ReferenceActivationState.isOpen`.
    @discardableResult
    public func handleInteraction(_ event: InteractionEvent) -> PapyrusActivationOutcome {
        let interaction = event.target.interaction
        guard
            let entry = bridge.ports.references?.referenceEntry(formID: interaction.reference)
        else { return .none }
        return activate(
            entry.key,
            by: bridge.playerKey,
            togglesOpen: interaction.action == .open
        )
    }
}
