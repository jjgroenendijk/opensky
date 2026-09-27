// The M15 gate's route, step by step (issue #198), in a satellite of
// `M15AcceptanceTests.swift` for the strict-lint type-length cap.
//
// One step per phase of the fight, each asserting what the engine holds before
// the next one runs, so a failure names the step rather than leaving an end
// state to reverse-engineer. The order is the order a session would fight in
// and is not rearrangeable: every step depends on the state the previous one
// left behind.

import Foundation
@testable import opensky
import simd
import Testing

@MainActor
extension M15AcceptanceTests {
    typealias Chain = M15AcceptanceChain
    typealias State = M15AcceptanceFixture.State

    /// Step 1 — nobody is pressing anything. Both graphs sit in their start
    /// state, the weapon is away, and nothing is in combat.
    static func standStill(_ chain: Chain) throws {
        chain.capturePointer()
        chain.run(frames: 10)

        #expect(chain.currentState == State.idle.name)
        #expect(chain.melee.state.drawState == .sheathed)
        #expect(!chain.combat.state.isPlayerInCombat)
        #expect(chain.playerHealth == Chain.playerHealth)
        #expect(chain.opponentHealth == Chain.opponentHealth)
        #expect(chain.controller.isGrounded)
    }

    /// Step 2 — R goes down on the real view. The melee runtime raises the two
    /// equip events, the graph plays its draw clip, and it is the clip's own
    /// `BeginWeaponDraw` annotation coming back that puts the weapon in the
    /// hand — not the key press.
    static func drawTheWeapon(_ chain: Chain) throws {
        chain.press(.keyR)
        chain.run(frames: 4)
        #expect(chain.currentState == State.draw.name, "the equip event did not move the graph")
        #expect(chain.melee.state.drawState == .drawing)

        #expect(
            chain.run(frames: 60) { chain.melee.state.drawState == .drawn },
            "the draw annotation never arrived"
        )
        #expect(chain.bridge.status.raisedEvents.contains(CombatGraphNames.weapEquip))
        // The draw clip runs on to its own end and hands the graph back before
        // the route presses anything else; see `settleGraph`.
        #expect(chain.settleGraph(), "the draw clip never handed the graph back")
        #expect(
            chain.graph.variable(named: CombatGraphNames.rightHandType)
                == .int(Int32(CombatHandType.sword.rawValue))
        )
    }

    /// Step 3 — the opponent is angered and starts swinging back. This is the
    /// same call `World > Combat & Physics > Combat Loop`'s hostility checkbox
    /// makes; the panel half drives it through the control.
    ///
    /// Since 16.7 that is the whole of it: hostility plus the opponent noticing
    /// the player is the fight, and there is no designation step in between.
    static func angerTheOpponent(_ chain: Chain) throws {
        chain.combat.setHostility(.hostile, on: Chain.opponent)
        #expect(chain.combatHostility(of: Chain.opponent) == .hostile)

        chain.run(frames: 4)
        #expect(chain.combat.state.isPlayerInCombat)
        #expect(chain.combat.state.target == Chain.opponent)
        #expect(chain.combat.phase(of: Chain.opponent)?.isEngaged == true)
    }

    /// Step 4 — one click. The melee runtime raises `attackStart`, the graph
    /// plays its attack clip, and the clip's own `HitFrame` annotation is what
    /// runs the sweep. Health comes off through the actor-value runtime, and
    /// the target's own graph takes the stagger.
    static func landASwing(_ chain: Chain) throws {
        chain.settleGraph()
        chain.clickAttack()
        #expect(
            chain.run(frames: 60) { chain.melee.hitCount == 1 },
            "the swing never reached a contact frame"
        )

        #expect(chain.visitedStates.contains(State.attack.name))
        #expect(chain.opponentHealth == Chain.opponentHealth - Chain.weaponDamage)
        let hit = try #require(chain.melee.trace.last)
        #expect(hit.target == Chain.opponent)
        #expect(hit.damage.applied == Chain.weaponDamage)
        #expect(!hit.damage.wasBlocked)
        // The stagger reached the opponent's own graph, which is what a second
        // graph in the route is for: an event raised on a target that has one
        // is taken by that target and by nobody else.
        #expect(hit.staggered)
        #expect(
            chain.run(frames: 30) { chain.opponentState == State.stagger.name },
            "the opponent never played its stagger"
        )
        #expect(chain.currentState != State.stagger.name, "the stagger reached the player")
    }

    /// Step 5 — the guard goes up on the right button and the opponent's next
    /// blow lands reduced. The reduction is the 15.4 formula, re-derived here
    /// rather than copied as a number.
    static func blockAnIncomingBlow(_ chain: Chain) throws {
        let before = chain.playerHealth
        chain.settleGraph()
        chain.setBlocking(true)
        chain.run(frames: 6)
        #expect(chain.melee.state.isBlocking)
        #expect(chain.bridge.status.raisedEvents.contains(CombatGraphNames.blockStart))

        #expect(
            chain.run(frames: 900) { chain.combat.incomingHitCount > 0 },
            "the opponent never landed a blow"
        )
        let blow = try #require(chain.combat.incomingTrace.last)
        let expected = MeleeDamage.resolve(
            weapon: MeleeWeaponProfile(damage: 6, reach: 1),
            block: .weapon,
            settings: .synthetic
        )
        #expect(blow.damage.wasBlocked)
        #expect(blow.damage == expected)
        #expect(chain.playerHealth == before - expected.applied)
        #expect(chain.playerHealth > 0, "the blocked blow was not reduced at all")

        chain.setBlocking(false)
        chain.run(frames: 6)
        #expect(!chain.melee.state.isBlocking)
    }

    /// Step 6 — back out of the opponent's reach and put the melee weapon
    /// away, which is what leaves the attack button to archery.
    ///
    /// Backing away first is the fight's own logic rather than a convenience:
    /// a bow is the answer to an opponent that is no longer next to you, and it
    /// is also what makes the arrow's flight a flight instead of a formality.
    /// A click with the weapon sheathed resolves nothing, which is what stops
    /// the same button swinging as well as drawing.
    static func switchToTheBow(_ chain: Chain) throws {
        let start = chain.feetPosition.x
        chain.press(.keyS)
        chain.run(frames: 90)
        chain.release(.keyS)
        chain.run(frames: 10)
        #expect(chain.feetPosition.x < start, "the player never backed away")
        let range = chain.opponentFeet.x - chain.feetPosition.x
        #expect(range > chain.melee.currentReach, "the opponent is still in reach")

        chain.settleGraph()
        chain.press(.keyR)
        #expect(
            chain.run(frames: 60) { chain.melee.state.drawState == .sheathed },
            "the sheathe annotation never arrived"
        )
        #expect(chain.visitedStates.contains(State.sheathe.name))
        #expect(chain.bridge.status.raisedEvents.contains(CombatGraphNames.unequip))
    }

    /// Step 7 — hold the button to draw, release to loose. The arrow leaves on
    /// the graph's own `arrowRelease` annotation, flies under gravity, and
    /// takes the opponent's last health off.
    static func landTheKillingArrow(_ chain: Chain) throws {
        let quiver = chain.inventory.count(of: Chain.arrowItem, in: .player)
        let swings = chain.melee.swingCount
        chain.settleGraph()
        chain.holdAttack()
        #expect(
            chain.run(frames: 60) { chain.archery.state.phase == .drawn },
            "the bow never reached full draw"
        )
        #expect(chain.visitedStates.contains(State.bowDraw.name))
        #expect(chain.melee.swingCount == swings, "a sheathed weapon still swung")

        chain.releaseAttack()
        #expect(
            chain.run(frames: 60) { chain.archery.projectiles.firedCount == 1 },
            "the release never put an arrow in the air"
        )
        #expect(chain.visitedStates.contains(State.bowRelease.name))
        #expect(chain.inventory.count(of: Chain.arrowItem, in: .player) == quiver - 1)

        #expect(
            chain.run(frames: 240) { chain.archery.projectiles.impactCount == 1 },
            "the arrow never landed"
        )
        let trace = try #require(chain.archery.projectiles.trace.last)
        #expect(trace.outcome == .hitActor)
        #expect(trace.target == Chain.opponent)
        #expect(trace.appliedDamage > 0)
        // The arrow is a ballistic body, so it ends below the line it was
        // aimed along; a shot with no drop would be a straight ray wearing an
        // arrow's name.
        #expect(trace.drop > 0)
        #expect(trace.travelled > 0)
        #expect(chain.opponentHealth == 0)
    }

    /// Step 8 — zero health is a death, the death is the graph's to play, and
    /// the physics takes the skeleton over on the graph's own hand-off
    /// annotation rather than on a timer.
    static func watchTheRagdollCollapse(_ chain: Chain) throws {
        #expect(
            chain.run(frames: 30) { chain.ragdolls.isDead(Chain.opponent) },
            "zero health never became a death"
        )
        #expect(chain.ragdolls.graphDrivenDeathCount == 1)
        #expect(chain.ragdolls.fallbackDeathCount == 0, "the graph-less fallback ran")

        #expect(
            chain.run(frames: 60) { chain.ragdolls.world.ragdollCount == 1 },
            "the hand-off annotation never spawned a ragdoll"
        )
        #expect(chain.opponentVisitedStates.contains(State.death.name))
        let stats = chain.ragdolls.world.statsSnapshot
        #expect(stats.boneBodyCount == 3)
        #expect(stats.jointCount == 2)
        #expect(stats.recoveredBodyCount == 0, "a bone integrated to a non-finite pose")

        #expect(
            chain.run(frames: 2000) { chain.ragdolls.world.statsSnapshot.settledRagdollCount == 1 },
            "the corpse never came to rest"
        )
        let settled = chain.ragdolls.world.statsSnapshot
        #expect(settled.jointViolationCount == 0, "the solver stopped with limits violated")
        #expect(settled.recoveredBodyCount == 0)
        let death = try #require(chain.deathStates[Chain.opponent])
        #expect(death.isDead)
        #expect(death.restingTransform != nil, "a settled corpse recorded no resting pose")
        // A dead opponent stops attacking, which is what ends the fight.
        chain.run(frames: 60)
        #expect(!chain.combat.state.isPlayerInCombat)
        #expect(chain.combat.state.deadCount == 1)
    }

    /// Step 9 — the corpse opens as a container and every item moves. Loot is
    /// conserved: what left the corpse is exactly what reached the player.
    static func lootTheCorpse(_ chain: Chain) throws {
        #expect(chain.ragdolls.opensAsCorpse(Chain.opponent))
        let carried = chain.inventory.count(of: Chain.lootItem, in: .player)
        let onCorpse = chain.inventory.count(of: Chain.lootItem, in: chain.corpseHolder)
        #expect(onCorpse == Chain.lootCount)

        try chain.inventory.transfer(
            Chain.lootItem, count: onCorpse, from: chain.corpseHolder, to: .player
        )
        chain.ragdolls.noteLooted(Chain.opponent)

        #expect(chain.inventory.count(of: Chain.lootItem, in: chain.corpseHolder) == 0)
        #expect(chain.inventory.count(of: Chain.lootItem, in: .player) == carried + onCorpse)
        #expect(chain.deathStates[Chain.opponent]?.wasLooted == true)
    }

    /// Step 10 — the crate the cell placed above the floor has fallen, come to
    /// rest, and stopped costing anything.
    static func settleTheClutter(_ chain: Chain) throws {
        #expect(
            chain.run(frames: 900) { chain.crateBody?.isSleeping == true },
            "the clutter never settled"
        )
        let crate = try #require(chain.crateBody)
        #expect(crate.position.z < M15AcceptanceWorld.clutterDropHeight, "the crate never fell")
        #expect(crate.position.z > M15AcceptanceWorld.floorHeight, "the crate fell through")
        #expect(crate.position.isFiniteVector)
        #expect(chain.streamer.dynamicBodies.statsSnapshot.recoveredBodyCount == 0)
        // Settling is what writes the resting pose into the world state, which
        // is what a save then carries.
        #expect(chain.store.component(ReferenceTransformOverride.self, for: Chain.crate) != nil)
    }

    /// Step 11 — the whole fight survives a round trip through the native save
    /// container: the corpse is still dead and still at rest, its inventory is
    /// still empty, and the crate is still where it stopped.
    static func saveAndLoad(_ chain: Chain) throws {
        chain.combat.prepareForPersistence()
        let snapshot = chain.store.snapshot()
        let bytes = OpenSkySaveEncoder.encode(
            snapshot: snapshot,
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata
        )
        let file = try OpenSkySaveDecoder.decode(bytes)
        #expect(file.snapshot == snapshot)

        let restored = WorldStateStore()
        restored.restore(from: file.snapshot)
        let death = try #require(restored.component(ActorDeathState.self, for: Chain.opponent))
        #expect(death.isDead)
        #expect(death.wasLooted)
        #expect(death.restingTransform != nil)
        let crate = try #require(
            restored.component(ReferenceTransformOverride.self, for: Chain.crate)
        )
        #expect(crate.position == chain.crateBody?.position)

        let inventory = try InventoryRuntime(
            store: restored, baselines: InventoryBaselineFixture.resolver()
        )
        #expect(inventory.count(of: Chain.lootItem, in: chain.corpseHolder) == 0)
        #expect(inventory.count(of: Chain.lootItem, in: .player) == Chain.lootCount)
        // Nothing that cannot survive a reload was written: the arrows and the
        // still-falling bodies are dropped on the way out, and the encode is
        // byte-stable so two saves of the same fight are the same file.
        #expect(chain.archery.projectiles.live.isEmpty)
        #expect(bytes == OpenSkySaveEncoder.encode(
            snapshot: snapshot,
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata
        ))
    }

    // MARK: - The claim

    /// Every state the milestone names was entered by one of the two graphs.
    /// The split matters: the player draws, swings, blocks and shoots, and the
    /// opponent staggers and dies, and a route that reached all of them on one
    /// graph would not have proved an event went to the right actor.
    static func expectEveryStateWasEntered(_ chain: Chain) {
        let player = Set(chain.visitedStates)
        for state in [State.idle, .draw, .sheathe, .attack, .block, .bowDraw, .bowRelease] {
            #expect(player.contains(state.name), "the player never entered \(state.name)")
        }
        let opponent = Set(chain.opponentVisitedStates)
        for state in [State.stagger, .death] {
            #expect(opponent.contains(state.name), "the opponent never entered \(state.name)")
        }
        #expect(!player.contains(State.death.name), "the player played the death animation")
        #expect(chain.bridge.status.missingVariables.isEmpty)
        #expect(chain.bridge.status.missingEvents.isEmpty)
        // Nothing in the route reached a class the evaluator has no semantics
        // for: the synthetic graph is made only of shapes OpenSky implements.
        #expect(chain.graph.tally.gapTotal == 0)
        #expect(chain.opponentGraph.tally.gapTotal == 0)
    }
}
