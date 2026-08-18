// Session wiring for actor values (issue #194, roadmap item 15.3): builds the
// runtime over the provider's RACE/CLAS/NPC_ indexes, ticks regeneration on the
// renderer's world-simulation delta, and publishes the player's values to the
// vanilla HUD meters.
//
// AppKit stays in this controller satellite; the derivation, the runtime and
// the meter binding are all engine types that build into `openskycli` and are
// testable without a window.
//
// The regeneration tick shares `Renderer.onWorldUpdate` with the Papyrus VM, so
// a menu-paused frame delivers delta 0 to both and neither advances. That is
// the established rule and it is why nothing here checks `menuMode` itself.

import AppKit
import OSLog

/// Actor-value state the controller owns. Extensions cannot add stored
/// properties, so it lives as one value on `GameViewController`.
struct ActorValueBridgeState {
    /// Damage/restore/regeneration runtime, built by `wireActorValues` when the
    /// provider can supply the record indexes. nil without game data.
    var runtime: ActorValueRuntime?
    /// Fixed-step accumulator for regeneration. Owned here rather than by the
    /// runtime because `ActorValueRuntime` is a struct over a shared store and
    /// a per-instance accumulator would split the simulation in half.
    var regenAccumulator: Double = 0
    /// Change gate in front of the HUD meter contract.
    var meters = HUDMeterBinding()
    /// Which target the panel's dev controls act on (item 15.9).
    var target = ActorValueTargetSelector.player
    /// Which actor value they act on, by vanilla table index (item 19.5).
    /// Health until the panel selects another.
    var selection: Int32 = 24
    /// Human-readable result of the last panel action.
    var lastActionText = "No actor-value action yet."
}

extension GameViewController {
    /// Builds the actor-value runtime over the provider's stat indexes.
    ///
    /// A provider with no indexes — every synthetic scene — leaves the runtime
    /// nil, and the panel then reports itself unavailable rather than showing a
    /// convincing zero.
    func wireActorValues(provider: any CellSceneProvider, renderer: Renderer) {
        guard
            let baselines = (provider as? ActorValueDataProviding)?.actorValueBaselines
        else {
            return
        }
        actorValues.runtime = ActorValueRuntime(store: worldState, baselines: baselines)
        // `onWorldUpdate` is a single closure and the Papyrus VM already owns
        // it, so this chains rather than replaces: both systems advance on the
        // same simulated delta, in wiring order, and neither can silently
        // unhook the other. The renderer gates that delta through its own
        // `FrameSimClock`, so a menu-paused frame delivers zero and
        // regeneration advances nothing.
        let advanceScripts = renderer.onWorldUpdate
        renderer.onWorldUpdate = { [weak self] delta in
            advanceScripts?(delta)
            self?.advanceActorValues(delta: delta)
        }
        renderer.onFrame.add { [weak self, weak renderer] _ in
            self?.publishHUDMeters(renderer: renderer)
        }
    }

    /// Runs whole regeneration steps for the delta this frame simulated.
    ///
    /// Only the player and the resident actors regenerate. An actor in a cell
    /// that is not loaded is not simulated at all in this engine, and pretending
    /// otherwise would mean walking every dirty reference in the store on every
    /// frame for a number nobody can observe.
    func advanceActorValues(delta: Float) {
        guard let runtime = actorValues.runtime else { return }
        // A caster does not regenerate. UESP states it flatly: "Magicka will not
        // regenerate while you are casting a spell."
        // (<https://en.uesp.net/wiki/Skyrim:Magicka>) The player is dropped from
        // the set entirely rather than having magicka regeneration suppressed on
        // its own, because the same paragraph names no other value and no source
        // says health and stamina keep going — see docs/engine/magic.md, which
        // records that as a stated deviation rather than a silent one.
        // Every caster, not only the player: item 19.10 casts an NPC's spells
        // through the same runtime, so a skeleton mid-charge stands down from
        // regeneration for the same cited reason the player does.
        let casting = casting.runtime
        let holders = regeneratingHolders().filter { casting?.isCasting($0.key) != true }
        runtime.advance(
            delta: delta,
            accumulator: &actorValues.regenAccumulator,
            over: holders
        )
    }

    /// Hands the player's meters to the movie when they changed this frame.
    func publishHUDMeters(renderer: Renderer?) {
        guard
            let renderer,
            hud.isLoaded,
            let runtime = actorValues.runtime,
            let meters = actorValues.meters.publishing(runtime.hudMeters(for: .player))
        else {
            return
        }
        do {
            try renderer.updateSWFRuntime { runtime in
                HUDMovieBridge.setMeters(meters, runtime: runtime)
            }
        } catch {
            Self.actorValueLogger.error(
                "[ERROR] HUD meters not published: \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// The player plus every resident actor, which is the set regeneration
    /// advances. Sorted by the runtime, not here.
    func regeneratingHolders() -> [ActorValueHolder] {
        var holders: [ActorValueHolder] = [.player]
        guard let streamer else { return holders }
        for entry in streamer.residentActorEntries() {
            guard let actor = entry.placedActor else { continue }
            holders.append(ActorValueHolder(
                key: entry.key,
                subject: .actor(base: actor.base),
                cell: streamer.cellLocation(of: entry.key)
            ))
        }
        return holders
    }

    /// The nearest resident actor as an actor-value holder, or nil when none is
    /// loaded.
    func nearestActorValueHolder() -> ActorValueHolder? {
        guard
            let streamer,
            let renderer,
            let entry = streamer.nearestActorEntry(to: renderer.freeFlyCamera.position),
            let actor = entry.placedActor
        else { return nil }
        return ActorValueHolder(
            key: entry.key,
            subject: .actor(base: actor.base),
            cell: streamer.cellLocation(of: entry.key)
        )
    }

    private static let actorValueLogger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "ActorValues"
    )
}
