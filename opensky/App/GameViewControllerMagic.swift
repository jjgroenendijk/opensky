// Session wiring for active magic effects (issue #469, roadmap item 19.6):
// builds the runtime over the provider's MGEF index and the actor-value runtime
// beside it, and ticks effects on the renderer's world-simulation delta.
//
// AppKit stays in this controller satellite; the runtime, the planner and the
// component are all engine types that build into `openskycli` and are testable
// without a window.
//
// The tick shares `Renderer.onWorldUpdate` with the Papyrus VM and with
// regeneration, so a menu-paused frame delivers delta 0 to all three and none of
// them advances. That is the established rule and it is why nothing here checks
// `menuMode` itself.

import AppKit

/// Active-effect state the controller owns. Extensions cannot add stored
/// properties, so it lives as one value on `GameViewController`.
struct MagicBridgeState {
    /// Apply/tick/dispel runtime, built by `wireMagicEffects` when the provider
    /// can supply an MGEF index and an actor-value runtime already exists. nil
    /// without game data.
    var runtime: ActiveEffectRuntime?
    /// Fixed-step accumulator, owned here rather than by the runtime for the
    /// reason regeneration's is: the runtime is a value over a shared store and
    /// a per-instance accumulator would split the simulation in half.
    var accumulator: Double = 0
    /// Plugin every magic item's EFID links are relative to.
    var pluginName = ""
    /// Human-readable result of the last panel or menu action.
    var lastActionText = "No magic action yet."
}

extension GameViewController {
    /// Builds the active-effect runtime over the provider's MGEF index.
    ///
    /// Wired after `wireActorValues`, because every application ultimately
    /// writes an actor value and the runtime takes that surface by value. A
    /// provider with no MGEF index — every synthetic scene — leaves the runtime
    /// nil, and the panel then reports itself unavailable rather than showing a
    /// convincing empty effect list.
    func wireMagicEffects(provider: any CellSceneProvider, renderer: Renderer) {
        guard
            let values = actorValues.runtime,
            let magic = provider as? MagicDataProviding,
            let store = magic.magicEffectStore,
            let pluginName = magic.magicItemPluginName
        else {
            return
        }
        magicEffects.runtime = ActiveEffectRuntime(values: values, effects: store)
        magicEffects.pluginName = pluginName
        // `onWorldUpdate` is a single closure that regeneration and the Papyrus
        // VM already own, so this chains rather than replaces: all three
        // advance on the same simulated delta, in wiring order.
        let advanceOthers = renderer.onWorldUpdate
        renderer.onWorldUpdate = { [weak self] delta in
            advanceOthers?(delta)
            self?.advanceMagicEffects(delta: delta)
        }
    }

    /// Runs whole effect steps for the delta this frame simulated.
    ///
    /// The same holder set regeneration advances: an actor in a cell that is
    /// not loaded is not simulated at all in this engine, and walking every
    /// dirty reference each frame for a number nobody can observe is the cost
    /// that rule exists to avoid.
    func advanceMagicEffects(delta: Float) {
        guard magicEffects.runtime != nil else { return }
        magicEffects.runtime?.advance(
            delta: delta,
            accumulator: &magicEffects.accumulator,
            over: regeneratingHolders()
        )
    }

    /// Consumes `item` from the player and applies it to the player.
    ///
    /// The one place the menu action and the panel button meet, so the two
    /// cannot diverge on what consuming means.
    ///
    /// - Returns: a human-readable outcome, which both surfaces show verbatim.
    @discardableResult
    func consumeMagicItem(_ item: FormID) -> String {
        guard magicEffects.runtime != nil, let world = worldItems.runtime else {
            magicEffects.lastActionText = "Magic effects unavailable: no game data loaded."
            return magicEffects.lastActionText
        }
        let name = worldItems.runtime?.inventory.baselines.items
            .definition(item)?.editorID ?? item.description
        do {
            let outcome = try magicEffects.runtime?.consume(
                item,
                from: world.player,
                on: .player,
                inventory: world.inventory,
                fromPlugin: magicEffects.pluginName
            )
            magicEffects.lastActionText = Self.consumeText(name: name, outcome: outcome)
        } catch {
            magicEffects.lastActionText = "Could not consume \(name): "
                + String(describing: error)
        }
        return magicEffects.lastActionText
    }

    /// The first ALCH or INGR the player carries, in the inventory's own stack
    /// order, or nil when they carry none.
    func firstCarriedMagicItem() -> FormID? {
        guard let world = worldItems.runtime else { return nil }
        let items = world.inventory.baselines.items
        return world.inventory.inventory(of: world.player).stacks
            .map(\.item)
            .sorted { $0.rawValue < $1.rawValue }
            .first { items.magicItemUse($0) != nil }
    }

    private static func consumeText(name: String, outcome: MagicItemConsumeOutcome?) -> String {
        guard let outcome else {
            return "Could not consume \(name)."
        }
        let stored = outcome.stored.count
        let verb = outcome.kind == .ingredient ? "Ate" : "Drank"
        return "\(verb) \(name): \(outcome.entryCount) effect entries, "
            + "\(stored) now running."
    }
}
