// Archery (issue #196, roadmap item 15.5, scope point 2): the runtime that
// turns a held attack button into census-named graph events, reads the graph's
// answer back, and fires a projectile on the frame the arrow leaves the string.
//
// The order every frame runs in, and why it is that order, is `MeleeCombatRuntime`'s:
//
//   1. `acceptFrame(_:)` — intent edges become raised events. The engine only
//      ever *asks*: it raises `bowDrawStart`, it does not decide that a draw
//      began.
//   2. the fixed steps advance the graph, and the graph fires whatever it fires.
//   3. `handleGraphEvents(_:)` — the drained names advance `ArcheryState` and,
//      on `arrowRelease`, assemble the shot and hand it to
//      `ProjectileRuntime`.
//
// So a draw the graph refuses — bow sheathed, staggered, no arrows — costs one
// ignored event and nothing else. There is no engine-side draw timer to get out
// of step with the animation.
//
// One thing *is* timed, and it is worth being explicit about why that is not a
// contradiction: how long the button was held. UESP's draw-damage formula is a
// function of exactly that, in frames, and it is the player's input being
// measured rather than the animation's phase. The graph is still what decides
// when the arrow leaves; the hold time only decides how hard it leaves.
//
// Main-actor, like the other directors, and driven from the frame the renderer
// already runs there.
//
// Documented in docs/engine/archery.md.

import Foundation

/// One frame of archery intent. Filled beside `MeleeIntent` from the same
/// drained camera input, because it is the same button: with a bow equipped the
/// attack press draws instead of swinging.
nonisolated struct ArcheryIntent: Equatable, Sendable {
    /// Attack button held. A level, not an edge — a bow is drawn for as long as
    /// it is held, which is what the draw-time damage curve measures.
    var drawing = false
    /// Whether a bow is what is equipped. False routes the same button to
    /// melee and leaves this runtime idle.
    var hasBowEquipped = false
    /// Seconds since the previous frame, for the hold clock.
    var deltaTime: Float = 0

    static let still = ArcheryIntent()
}

@MainActor
final class ArcheryRuntime {
    let settings: ArcherySettings
    /// The projectile side, which owns everything already in the air.
    let projectiles: ProjectileRuntime

    private(set) var state = ArcheryState()
    /// How long the attack button has been held on the current draw, seconds.
    private(set) var heldSeconds: Float = 0
    /// The hold time of the last shot that was loosed, so a readout can explain
    /// a damage number after the button has already come back up.
    private(set) var lastHeldSeconds: Float = 0
    /// Draws the engine asked for, and shots the graph actually loosed. The two
    /// differ by every draw that was cancelled.
    private(set) var drawRequestCount = 0

    /// The bow the player is holding, as a swing profile — the same value melee
    /// resolves, because a bow is a WEAP and its `damage` and `speed` are the
    /// two numbers the archery formulas need. The unarmed profile until
    /// equipment resolves, and then no shot can be taken.
    var bow = MeleeWeaponProfile.unarmed
    /// The arrow the player has selected: its AMMO damage, the PROJ it
    /// launches, and the FormID the inventory consumes. Nil with an empty
    /// quiver, and then a draw is allowed and a loose does nothing.
    var arrow: ArcheryAmmunition?
    /// The shooter's fortify multiplier — `ArcheryDamage`'s `bonusMultiplier`
    /// (issue #472).
    ///
    /// A written property rather than a world seam, for the reason `bow` and
    /// `arrow` are: the session refreshes all three on the same frame, from the
    /// same equipment, and a runtime that asked for it would need an actor-value
    /// surface it otherwise has no use for. 1 until something writes it, which is
    /// what the formula reduces to for a shooter with no fortify effect.
    var attackMultiplier: Float = 1

    private weak var world: (any ProjectileWorld)?
    private var wasDrawing = false

    init(
        settings: ArcherySettings,
        projectiles: ProjectileRuntime,
        world: (any ProjectileWorld)? = nil
    ) {
        self.settings = settings
        self.projectiles = projectiles
        self.world = world
    }

    /// Attaches (or detaches) the world both halves resolve against.
    func attach(world: (any ProjectileWorld)?) {
        self.world = world
        projectiles.attach(world: world)
        reset()
    }

    // MARK: - Intent

    /// Takes one frame of archery intent and raises the events its edges imply.
    func acceptFrame(_ intent: ArcheryIntent) {
        let drawing = intent.drawing && intent.hasBowEquipped
        if drawing {
            heldSeconds += max(0, intent.deltaTime.isFinite ? intent.deltaTime : 0)
        }
        raiseIntentEvents(drawing: drawing)
        wasDrawing = drawing
        writeVariables()
    }

    /// Abandons the draw in progress, raising `bowReset`. What a sheath or a
    /// stagger calls, and what the panel's cancel control calls.
    func cancelDraw() {
        guard state.phase.isDrawing || wasDrawing else { return }
        wasDrawing = false
        heldSeconds = 0
        world?.raiseArcheryEvent(ArcheryGraphNames.bowReset)
    }

    // MARK: - Graph events

    /// Advances the shot state by one frame's drained graph events, firing a
    /// projectile on every release among them.
    ///
    /// - Returns: the projectiles this frame launched, in the order the graph
    ///   released them.
    @discardableResult
    func handleGraphEvents(_ names: [String]) -> [LiveProjectile] {
        var launched: [LiveProjectile] = []
        for change in state.handle(names) where change.loosedArrow {
            if let projectile = loose() {
                launched.append(projectile)
            }
        }
        state.endFrame()
        writeVariables()
        return launched
    }

    /// Assembles and fires the shot the current draw earned, whatever released
    /// it.
    ///
    /// Public so the panel's dev spawn control reaches the same code path the
    /// graph does — a shot requested from the sidebar has to be
    /// indistinguishable downstream from one the player took, which is the
    /// whole point of offering the control.
    ///
    /// - Parameter consumesArrow: false spawns without touching the quiver,
    ///   which is what the dev control wants and what a real shot must never do.
    @discardableResult
    func loose(consumesArrow: Bool = true) -> LiveProjectile? {
        guard let arrow else { return nil }
        lastHeldSeconds = heldSeconds
        let shot = ProjectileShot.arrow(
            profile: arrow.profile,
            damage: ArcheryDamage.resolve(
                bowDamage: bow.damage,
                arrowDamage: arrow.damage,
                drawFraction: ArcheryDamage.drawFraction(
                    heldSeconds: heldSeconds, speed: bow.speed
                ),
                bonusMultiplier: attackMultiplier
            ),
            weapon: bow.weapon,
            ammunition: consumesArrow ? arrow.item : nil,
            enchantment: bow.enchantment
        )
        heldSeconds = 0
        return projectiles.fire(shot)
    }

    /// One frame of flight for everything already in the air.
    @discardableResult
    func advanceProjectiles(by frameTime: Float) -> [ProjectileTrace] {
        projectiles.advance(by: frameTime)
    }

    /// Forgets the draw and everything in the air. Called when the bridge
    /// resets, so a teleport cannot land an arrow fired in the cell that was
    /// just left.
    func reset() {
        state.reset()
        heldSeconds = 0
        lastHeldSeconds = 0
        drawRequestCount = 0
        wasDrawing = false
        projectiles.despawnAll()
    }

    // MARK: - Private

    /// Raises the events this frame's intent edges imply.
    private func raiseIntentEvents(drawing: Bool) {
        guard let world, drawing != wasDrawing else { return }
        if drawing {
            drawRequestCount += 1
            world.raiseArcheryEvent(ArcheryGraphNames.bowDrawStart)
        } else {
            world.raiseArcheryEvent(ArcheryGraphNames.attackRelease)
        }
    }

    /// Publishes the shot state into the graph variables the census names.
    private func writeVariables() {
        world?.writeArcheryVariable(
            .bool(state.phase.isFullyDrawn), named: ArcheryGraphNames.isBowDrawn
        )
    }
}

/// The selected arrow, reduced to what a shot needs from it.
nonisolated struct ArcheryAmmunition: Equatable, Sendable {
    /// The AMMO itself, which is what the inventory consumes.
    let item: FormID
    /// AMMO DATA base damage.
    let damage: Float
    /// The PROJ it launches, already decoded into a flight profile.
    let profile: ProjectileProfile

    init(item: FormID, damage: Float, profile: ProjectileProfile) {
        self.item = item
        self.damage = damage.isFinite ? max(0, damage) : 0
        self.profile = profile
    }

    /// One decoded AMMO plus the PROJ it names.
    init(ammunition: Ammunition, projectile: Projectile) {
        self.init(
            item: ammunition.formID,
            damage: ammunition.damage,
            profile: ProjectileProfile(record: projectile)
        )
    }
}
