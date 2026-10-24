// Archery: a held button becomes raised graph events, and a projectile fires on the
// graph's `arrowRelease`. Each frame: `acceptFrame(_:)` raises, fixed steps advance the
// graph, `handleGraphEvents(_:)` reacts. A refused draw costs one ignored event. Only the
// hold time is measured, because UESP's draw damage depends on it.
// See docs/engine/archery.md.

import Foundation
import OpenSkyActorsInterface
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
    /// The draw share of the last shot, below 1 for a dud: Papyrus `OnPlayerBowShot`'s power.
    public private(set) var lastDrawFraction: Float = 1
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
    /// quiver, and then a press shows `sNoArrows` instead of drawing.
    public var arrow: ArcheryAmmunition?
    /// The shooter's fortify multiplier, `ArcheryDamage`'s `bonusMultiplier`. Written by
    /// the session on the same frame as `bow` and `arrow`; 1 until then.
    public var attackMultiplier: Float = 1
    /// What the zoom reads besides the keys: the perk share, stamina, and Slow Time.
    /// Written by the session each frame, like `attackMultiplier`.
    public var zoomConditions = BowZoomInput()
    public private(set) var zoom = BowZoom()

    private weak var world: (any ProjectileWorld)?
    private var wasDrawing = false
    private var wasPressed = false

    public init(
        settings: ArcherySettings,
        projectiles: ProjectileRuntime,
        world: (any ProjectileWorld)? = nil
    ) {
        self.settings = settings
        self.projectiles = projectiles
        self.world = world
    }

    // MARK: - Intent

    /// Takes one frame of archery intent and raises the events its edges imply.
    public func acceptFrame(_ intent: ArcheryIntent) {
        let pressed = intent.drawing && intent.hasBowEquipped
        if pressed, !wasPressed, arrow == nil {
            let arrows = projectiles.arrows
            world?.showArcheryNotice(
                bow.handType == .crossbow ? arrows.noBoltsText : arrows.noArrowsText
            )
        }
        wasPressed = pressed
        let drawing = pressed && arrow != nil
        if drawing {
            heldSeconds += max(0, intent.deltaTime.isFinite ? intent.deltaTime : 0)
        }
        raiseIntentEvents(drawing: drawing)
        wasDrawing = drawing
        var conditions = zoomConditions
        conditions.blockHeld = intent.zooming && intent.hasBowEquipped
        conditions.aiming = drawing || state.phase.isDrawing
        zoom.update(conditions)
        writeVariables()
    }

    /// Abandons the draw in progress, raising `bowReset`. What a sheath or a
    /// stagger calls, and what the readout's cancel control calls.
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
        let stop = ArcheryGraphNames.bowZoomStop
        if names.contains(where: { $0.caseInsensitiveCompare(stop) == .orderedSame }) {
            zoom.stop()
        }
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
        lastDrawFraction = ArcheryDamage.drawFraction(heldSeconds: heldSeconds, speed: bow.speed)
        let shot = ProjectileShot.arrow(
            profile: arrow.profile,
            damage: ArcheryDamage.resolve(
                bowDamage: bow.damage,
                arrowDamage: arrow.damage,
                drawFraction: lastDrawFraction,
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
        wasPressed = false
        zoom = BowZoom()
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
