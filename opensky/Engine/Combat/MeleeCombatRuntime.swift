// Melee combat (issue #195, roadmap item 15.4): the runtime that turns player
// intent into census-named graph events, reads the graph's answer back, and
// resolves the hit the contact frame asks for.
//
// The order every frame runs in, and why it is that order:
//
//   1. `acceptFrame(_:)` — intent edges become raised events. The engine only
//      ever *asks*: it raises `attackStart`, it does not decide that an attack
//      began.
//   2. the fixed steps advance the graph (LocomotionBridge's job, not this
//      type's), and the graph fires whatever it fires.
//   3. `handleGraphEvents(_:)` — the drained names advance `MeleeCombatState`
//      and, on the contact frame, run the sweep and apply the damage.
//
// So a swing that the graph refuses — sheathed, staggered, already swinging —
// costs one ignored event and nothing else. There is no engine-side attack
// timer to get out of step with the animation, which is the same rule the
// footstep director follows.
//
// Main-actor, like the other directors, and driven from the frame the renderer
// already runs there. Everything it touches the world with goes through
// `MeleeCombatWorld`, so the whole runtime is testable against a fake.
//
// Documented in docs/engine/melee-combat.md.

import Foundation
import simd

@MainActor
final class MeleeCombatRuntime {
    /// How many hit records the trace keeps. A swing through a crowd lands
    /// several at once, so this is a handful of swings rather than a handful
    /// of hits.
    static let traceLimit = 16

    let settings: CombatSettings
    private(set) var state = MeleeCombatState()
    /// The most recent landed hits, oldest first.
    private(set) var trace: [MeleeHitRecord] = []
    /// Swings that reached their contact frame, and hits those swings landed.
    /// The two differ by every swing that connected with nothing, which is
    /// most of them.
    private(set) var swingCount = 0
    private(set) var hitCount = 0

    /// The weapon the player is swinging. Written when equipment resolves; the
    /// unarmed profile until then. Its `handType` is what `iRightHandType`
    /// reports, so the graph plays that weapon's own equip and attack clips.
    var weapon = MeleeWeaponProfile.unarmed

    /// What the left hand is holding, written to `iLeftHandType`. Separate from
    /// `weapon` because the left hand holds things a `MeleeWeaponProfile`
    /// cannot describe — a shield, a torch, a readied spell — and because a
    /// two-handed weapon occupies both hands while still being one profile.
    /// Empty until equipment resolves one.
    var offHand = CombatHandType.handToHand

    /// Resolves the IPCT chain for a landed hit. Nil in a synthetic session,
    /// and then hits are silent rather than absent.
    var impacts: MeleeImpactResolver?

    /// Holds the guard up from something other than the mouse button. Ored
    /// with the frame's intent, so releasing the button does not drop a guard
    /// a probe or a headless driver put up.
    var panelBlocking = false

    private weak var world: (any MeleeCombatWorld)?
    /// Targets this swing has already landed on, cleared when the swing id
    /// changes. Keyed by reference rather than by index, so a target that
    /// leaves and re-enters the list mid-swing is still only hit once.
    private var hitThisSwing: Set<ReferenceKey> = []
    private var hitSwingID = 0
    /// Intent edges, so an event is raised on the change rather than every
    /// frame.
    private var wasBlocking = false
    private var pendingAttack = false
    private var pendingToggle = false

    init(settings: CombatSettings, world: (any MeleeCombatWorld)? = nil) {
        self.settings = settings
        self.world = world
    }

    /// Attaches (or detaches) the world this runtime resolves against.
    func attach(world: (any MeleeCombatWorld)?) {
        self.world = world
        reset()
    }

    // MARK: - Intent

    /// Takes one frame of melee intent and raises the events its edges imply.
    ///
    /// Both one-shot presses latch rather than being consumed here, for the
    /// same reason jump does: a press between two rendered frames must still
    /// reach the graph, and must reach it exactly once.
    func acceptFrame(_ intent: MeleeIntent) {
        if intent.attack {
            requestAttack()
        }
        if intent.toggleWeaponDrawn {
            requestWeaponToggle()
        }
        // Variables before events, the same write-then-raise order the stagger
        // path uses: the equip event a draw raises is acted on against the hand
        // types, so a frame that equips a sword and draws it in one go must not
        // let the graph read the previous hand's number.
        writeVariables()
        raiseIntentEvents(blocking: intent.block || panelBlocking)
    }

    /// Latches one swing. What the panel's Attack button calls; the mouse
    /// button reaches the same latch through `acceptFrame(_:)`, so a swing
    /// requested from the sidebar is indistinguishable from one the player
    /// made.
    func requestAttack() {
        pendingAttack = true
    }

    /// Latches one draw or sheath, whichever the current state implies.
    func requestWeaponToggle() {
        pendingToggle = true
    }

    /// Asks for a specific draw state rather than a toggle, which is what a
    /// checkbox means. A request that matches the current state does nothing.
    func setWeaponDrawn(_ drawn: Bool) {
        guard drawn != state.drawState.isWeaponInHand else { return }
        requestWeaponToggle()
    }

    /// Empties the trace and both counts without disturbing anything the
    /// player can feel, which is what the panel's own clear control does.
    func clearTrace() {
        trace = []
        swingCount = 0
        hitCount = 0
    }

    // MARK: - Graph events

    /// Advances the melee state by one frame's drained graph events, resolving
    /// a hit on every contact frame among them.
    ///
    /// - Returns: the hits this frame landed, in the order they were resolved.
    @discardableResult
    func handleGraphEvents(_ names: [String]) -> [MeleeHitRecord] {
        var landed: [MeleeHitRecord] = []
        for change in state.handle(names) where change.openedHitWindow {
            swingCount += 1
            landed += resolveSwing()
        }
        state.endFrame()
        writeVariables()
        return landed
    }

    /// Forgets every edge and every in-flight swing. Called when the bridge
    /// resets, so a teleport cannot land the hit the swing before it was
    /// interrupted by.
    func reset() {
        state.reset()
        trace = []
        swingCount = 0
        hitCount = 0
        hitThisSwing = []
        hitSwingID = 0
        wasBlocking = false
        pendingAttack = false
        pendingToggle = false
    }

    // MARK: - Readout

    /// Where the swing would reach right now, for the panel and the tests.
    var currentReach: Float {
        MeleeSwing.reach(
            weapon: weapon,
            settings: settings,
            actorScale: world?.meleeAttacker.scale ?? 1
        )
    }

    // MARK: - Private

    /// Raises the events this frame's intent edges imply, in a fixed order so
    /// a frame that changes several things at once produces the same sequence
    /// on every run.
    private func raiseIntentEvents(blocking: Bool) {
        guard let world else { return }
        if pendingToggle {
            pendingToggle = false
            raiseEquipEvents(sheathing: state.drawState.isWeaponInHand, world: world)
        }
        if blocking != wasBlocking {
            wasBlocking = blocking
            world.raiseCombatEvent(
                blocking ? CombatGraphNames.blockStart : CombatGraphNames.blockStop,
                on: nil
            )
        }
        if pendingAttack {
            pendingAttack = false
            // Dropped rather than queued when the weapon is away: a press that
            // sat in a latch would fire a swing the moment the draw finished,
            // seconds after the player asked for it.
            if state.drawState.canAttack, !state.attackPhase.isAttacking {
                world.raiseCombatEvent(CombatGraphNames.attackStart, on: nil)
            }
        }
    }

    /// Raises the pair of events one draw or sheath request implies.
    ///
    /// Two events rather than one, because the vanilla graph splits the job in
    /// two and only reads one of them. `weaponDraw` and `weaponSheathe` are
    /// declared but named by no transition in any character behavior file: they
    /// are the *intent*, and vanilla's engine, not its graph, decides what that
    /// intent equips. The second event is that decision, and it is the one
    /// `0_master.hkx` transitions on (issue #403).
    private func raiseEquipEvents(sheathing: Bool, world: any MeleeCombatWorld) {
        world.raiseCombatEvent(
            sheathing ? CombatGraphNames.weaponSheathe : CombatGraphNames.weaponDraw,
            on: nil
        )
        if sheathing {
            // One name for both branches: `Weap_Readied_State` and
            // `Magic_Behavior_State` each carry an `Unequip` transition.
            world.raiseCombatEvent(CombatGraphNames.unequip, on: nil)
        } else {
            world.raiseCombatEvent(
                weapon.handType.drawsAsMagic
                    ? CombatGraphNames.magicEquip
                    : CombatGraphNames.weapEquip,
                on: nil
            )
        }
    }

    /// Publishes the melee state into the graph variables the census names.
    private func writeVariables() {
        guard let world else { return }
        world.writeCombatVariable(
            .bool(state.attackPhase.isAttacking), named: CombatGraphNames.isAttacking
        )
        world.writeCombatVariable(
            .bool(state.isBlocking), named: CombatGraphNames.isBlocking
        )
        world.writeCombatVariable(
            .bool(state.isStaggering), named: CombatGraphNames.isStaggering
        )
        world.writeCombatVariable(
            .real(weapon.speed), named: CombatGraphNames.weaponSpeedMult
        )
        world.writeCombatVariable(
            weapon.handType.graphValue, named: CombatGraphNames.rightHandType
        )
        world.writeCombatVariable(
            offHand.graphValue, named: CombatGraphNames.leftHandType
        )
    }

    /// Runs the sweep for the swing now at its contact frame and applies every
    /// hit it found.
    private func resolveSwing() -> [MeleeHitRecord] {
        guard let world else { return [] }
        if hitSwingID != state.swingID {
            hitSwingID = state.swingID
            hitThisSwing = []
        }
        let attacker = world.meleeAttacker
        let volume = MeleeSwing.volume(
            feet: attacker.feet,
            capsule: attacker.capsule,
            facing: attacker.facing,
            reach: MeleeSwing.reach(
                weapon: weapon, settings: settings, actorScale: attacker.scale
            )
        )
        let hits = MeleeHitDetector.hits(
            swing: volume,
            targets: world.meleeTargets(),
            attacker: attacker.key,
            alreadyHit: hitThisSwing
        )
        return hits.map { apply($0, world: world) }
    }

    /// Damage, stagger and impact sound for one hit.
    private func apply(_ hit: MeleeHit, world: any MeleeCombatWorld) -> MeleeHitRecord {
        hitThisSwing.insert(hit.target)
        hitCount += 1
        let damage = MeleeDamage.resolve(
            weapon: weapon,
            block: world.meleeBlock(of: hit.target),
            settings: settings
        )
        world.applyMeleeDamage(damage.applied, to: hit.target)
        // After the damage, so a script that reads the target's health inside
        // `OnHit` sees the blow that caused the event rather than the state
        // before it (issue #375). The block term is what the damage formula
        // already resolved, so `abHitBlocked` cannot disagree with the number.
        world.reportScriptHit(ScriptHitEvent(
            target: hit.target,
            aggressor: world.meleeAttacker.key,
            source: weapon.weapon,
            isBlocked: damage.wasBlocked
        ))
        let staggered = stagger(hit.target, damage: damage, world: world)
        let impact = impacts?.resolve(
            weapon: weapon, material: world.meleeMaterial(at: hit.position)
        )
        if let impact {
            world.playMeleeImpact(impact, at: hit.position)
        }
        let record = MeleeHitRecord(
            target: hit.target,
            distance: hit.distance,
            position: hit.position,
            damage: damage,
            sound: impact?.sound,
            staggered: staggered,
            swingID: state.swingID
        )
        trace.append(record)
        if trace.count > Self.traceLimit {
            trace.removeFirst(trace.count - Self.traceLimit)
        }
        return record
    }

    /// Tells the target's graph to stagger, if the weapon carries any stagger
    /// at all and the hit was not blocked away.
    ///
    /// `staggerMagnitude` is written before the event so the stagger behavior
    /// reads this hit's magnitude rather than the previous one's, which is the
    /// same write-then-raise order the locomotion bridge uses for every step.
    private func stagger(
        _ target: ReferenceKey,
        damage: MeleeDamageResult,
        world: any MeleeCombatWorld
    ) -> Bool {
        guard weapon.stagger > 0, damage.applied > 0 else { return false }
        world.writeCombatVariable(
            .real(weapon.stagger), named: CombatGraphNames.staggerMagnitude
        )
        return world.raiseCombatEvent(CombatGraphNames.staggerStart, on: target)
    }
}
