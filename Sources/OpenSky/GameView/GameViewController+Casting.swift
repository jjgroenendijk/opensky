// Session wiring for the caster runtime: builds the spellbook and the cast loop
// over the provider's SPEL and EQUP indexes, and feeds the loop each frame's
// cast intent. The hook shares `Renderer.onFrame` with melee, because a cast is
// timed against the rendered frame until the magic behavior graph drives it.
// Cast effects go through the same `ActiveEffectRuntime` as potions.

import AppKit
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyRendering
import OpenSkyWorld
import OpenSkyWorldState

/// Casting state the controller owns. Extensions cannot add stored properties,
/// so it lives as one value on `GameViewController`.
struct CastingBridgeState {
    /// Spellbook + cast loop, built by `wireCasting` when the provider can
    /// supply a spell index and an actor-value runtime already exists. nil
    /// without game data.
    var runtime: CasterRuntime?
    /// Which known spell the panel's Ready buttons act on, as an index into the
    /// player's known list. Clamped on read, so forgetting a spell cannot leave
    /// the selection past the end.
    var selection = 0
    /// Human-readable result of the last panel action.
    var lastActionText = "No casting action yet."
    /// Record-side resolution of an actor's authored `SPLO` list (issue #473),
    /// built beside the runtime from the same provider indexes the actor-value
    /// baselines come from. nil without game data.
    var spellBaselines: ActorSpellBaselineResolver?
    /// The plugin an actor's `SPLO` links are relative to, which is the base
    /// plugin the record indexes were built from.
    var spellPluginName: String?
    /// Actors whose authored spell list has already been granted, so the grant
    /// happens once per actor per session rather than once per combat step.
    var grantedActors: Set<ReferenceKey> = []
}

extension GameViewController {
    /// Wired after `wireMagicEffects`, because a cast applies its effects
    /// through that runtime. Without a spell index the runtime stays nil, and
    /// the panel says so rather than showing an empty spellbook.
    func wireCasting(provider: any WorldDataProviding, renderer: Renderer) {
        guard
            let values = actorValues.runtime,
            let magic = provider as? MagicDataProviding,
            let spells = magic.spellStore,
            let equipSlots = magic.equipSlotStore
        else {
            return
        }
        let spellbook = SpellbookRuntime(
            store: worldState,
            spells: spells,
            equipSlots: equipSlots,
            equipment: worldItems.equipment
        )
        let runtime = CasterRuntime(spellbook: spellbook, values: values)
        casting.runtime = runtime
        casting.spellPluginName = magic.magicItemPluginName
        if
            let resolver = (provider as? ActorValueDataProviding)?
                .actorValueBaselines?.resolver
        {
            casting.spellBaselines = ActorSpellBaselineResolver(actorValues: resolver)
        }
        runtime.attach(world: self)
        renderer.onFrame.add { [weak self, weak renderer] _ in
            self?.advanceCasting(renderer: renderer)
        }
    }

    /// One frame of casting: held buttons in, charges and drains advanced.
    ///
    /// Only while the player is controlled, matching melee: a frame spent in a
    /// menu or in free-fly must not charge a spell.
    func advanceCasting(renderer: Renderer?) {
        guard let renderer, let runtime = casting.runtime else { return }
        guard renderer.movementMode.isPlayerControlled else {
            runtime.acceptFrame(.still, on: .player)
            advanceActorCasts(delta: renderer.locomotion.archeryIntent.deltaTime)
            return
        }
        let melee = renderer.locomotion.meleeIntent
        let delta = renderer.locomotion.archeryIntent.deltaTime
        runtime.acceptFrame(
            CastingIntent(
                leftHeld: melee.block,
                rightHeld: renderer.locomotion.archeryIntent.drawing,
                deltaTime: delta
            ),
            on: .player
        )
        advanceActorCasts(delta: delta)
    }

    /// Every NPC cast in flight, charged on the player's clock. The player's
    /// frame hook advances only the player.
    func advanceActorCasts(delta: Float) {
        guard let runtime = casting.runtime, delta > 0 else { return }
        for key in runtime.castingActors where key != .player {
            guard let holder = actorValueHolder(for: key) else { continue }
            runtime.advance(delta: delta, on: holder)
        }
    }

    /// Whether the hand `hand` holds a readied spell, which is what routes its
    /// button to the cast loop instead of to melee.
    func hasReadiedSpell(in hand: SpellHand) -> Bool {
        guard let runtime = casting.runtime else { return false }
        return runtime.spellbook.state(of: .player).spell(in: hand) != nil
    }

    /// The player's known spells this load order can still resolve.
    func playerKnownSpells() -> [ResolvedSpell] {
        casting.runtime?.spellbook.knownSpells(of: .player) ?? []
    }

    /// The spell the panel's Ready buttons act on, or nil when nothing is known.
    func selectedKnownSpell() -> ResolvedSpell? {
        let known = playerKnownSpells()
        guard !known.isEmpty else { return nil }
        return known[min(max(0, casting.selection), known.count - 1)]
    }

    /// Every spell tome the player carries, in FormID order.
    func carriedSpellTomes() -> [(item: FormID, spell: FormID)] {
        guard let world = worldItems.runtime else { return [] }
        let items = world.inventory.baselines.items
        return world.inventory.inventory(of: world.player).stacks
            .map(\.item)
            .sorted { $0.rawValue < $1.rawValue }
            .compactMap { item in
                items.teachesSpell(item).map { (item: item, spell: $0) }
            }
    }
}

extension GameViewController: CasterWorld {
    /// Whole game days elapsed, which the once-per-day power rule compares.
    var castingGameDay: Int32 {
        Int32(clampedGameDay: renderer?.gameClock.daysPassed ?? 0)
    }

    func applyCastEffects(
        _ entries: [MagicItemEffect],
        fromPlugin pluginName: String,
        source: ActiveEffectSource,
        caster: ReferenceKey,
        on target: ActorValueHolder
    ) -> Int {
        guard magicEffects.runtime != nil else { return 0 }
        let stored = magicEffects.runtime?.apply(
            entries,
            fromPlugin: pluginName,
            source: source,
            caster: caster,
            on: target
        )
        return stored?.count ?? 0
    }

    /// Aimed fire-and-forget delivery: the MGEF's PROJ through the archery
    /// pipeline (issue #471).
    @discardableResult
    func fireSpellProjectile(_ payload: SpellPayload) -> Bool {
        launchSpellProjectile(payload)
    }

    /// Target-actor delivery and aimed concentration: whatever the caster's
    /// ray reaches — the camera's for the player, the actor's own for an NPC.
    func aimedSpellTarget(within range: Float, for caster: ReferenceKey) -> SpellAim {
        aimedTarget(within: range, for: caster)
    }
}

nonisolated extension Int32 {
    /// The whole day a `GameClock.daysPassed` reading names, clamped into range
    /// so a corrupt or absurd clock cannot trap the conversion.
    init(clampedGameDay days: Float) {
        guard days.isFinite else {
            self = 0
            return
        }
        let whole = days.rounded(.down)
        self = if whole <= Float(Int32.min) {
            Int32.min
        } else if whole >= Float(Int32.max) {
            Int32.max
        } else {
            Int32(whole)
        }
    }
}
