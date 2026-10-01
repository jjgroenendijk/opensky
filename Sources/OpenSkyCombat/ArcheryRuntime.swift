// Archery: a held button becomes raised graph events, and a projectile fires on the
// graph's `arrowRelease`. Each frame: `acceptFrame(_:)` raises, fixed steps advance the
// graph, `handleGraphEvents(_:)` reacts. A refused draw costs one ignored event. Only the
// hold time is measured, because UESP's draw damage depends on it.
// See docs/engine/archery.md.

import Foundation
import OpenSkyBehavior
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData

@MainActor
public final class ArcheryRuntime {
    public let settings: ArcherySettings
    /// The projectile side, which owns everything already in the air.
    public let projectiles: ProjectileRuntime

    public private(set) var state = ArcheryState()
    /// How long the attack button has been held on the current draw, seconds.
    public private(set) var heldSeconds: Float = 0
    /// The hold time of the last shot that was loosed, so a readout can explain
    /// a damage number after the button has already come back up.
    public private(set) var lastHeldSeconds: Float = 0
    /// Draws the engine asked for, and shots the graph actually loosed. The two
    /// differ by every draw that was cancelled.
    public private(set) var drawRequestCount = 0

    /// The bow the player is holding, as a swing profile — the same value melee
    /// resolves, because a bow is a WEAP and its `damage` and `speed` are the
    /// two numbers the archery formulas need. The unarmed profile until
    /// equipment resolves, and then no shot can be taken.
    public var bow = MeleeWeaponProfile.unarmed
    /// The arrow the player has selected: its AMMO damage, the PROJ it
    /// launches, and the FormID the inventory consumes. Nil with an empty
    /// quiver, and then a draw is allowed and a loose does nothing.
    public var arrow: ArcheryAmmunition?
    /// The shooter's fortify multiplier, `ArcheryDamage`'s `bonusMultiplier`. Written by
    /// the session on the same frame as `bow` and `arrow`; 1 until then.
    public var attackMultiplier: Float = 1

    private weak var world: (any ProjectileWorld)?
    private var wasDrawing = false

    public init(
        settings: ArcherySettings,
        projectiles: ProjectileRuntime,
        world: (any ProjectileWorld)? = nil
    ) {
        self.settings = settings
        self.projectiles = projectiles
        self.world = world
    }

    /// Attaches (or detaches) the world both halves resolve against.
    public func attach(world: (any ProjectileWorld)?) {
        self.world = world
        projectiles.attach(world: world)
        reset()
    }

    // MARK: - Intent

    /// Takes one frame of archery intent and raises the events its edges imply.
    public func acceptFrame(_ intent: ArcheryIntent) {
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
    public func cancelDraw() {
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
    public func handleGraphEvents(_ names: [String]) -> [LiveProjectile] {
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

    /// Assembles and fires the shot the current draw earned. Public, so the dev spawn
    /// uses the same path. `consumesArrow` false skips the quiver; real shots never do.
    @discardableResult
    public func loose(consumesArrow: Bool = true) -> LiveProjectile? {
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
    public func advanceProjectiles(by frameTime: Float) -> [ProjectileTrace] {
        projectiles.advance(by: frameTime)
    }

    /// Forgets the draw and everything in the air. Called when the bridge
    /// resets, so a teleport cannot land an arrow fired in the cell that was
    /// just left.
    public func reset() {
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
