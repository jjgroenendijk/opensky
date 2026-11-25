// Each NPC's weapon draw state: drawing when its fight starts, sheathing when it ends.
// See docs/engine/condition-functions-world.md#combat-actions.

public import OpenSkyActorsInterface
import OpenSkyBehavior
import OpenSkyCombatInterface
public import OpenSkyFormatsESM

extension CombatLoopRuntime {
    /// Where the weapon of the NPC `key` is. Nil for the player, whose melee state
    /// tracks its own draw.
    public func drawState(of key: ReferenceKey) -> WeaponDrawState? {
        key == .player ? nil : weaponDraws[key]?.state ?? .sheathed
    }

    /// One fixed step of every tracked draw. An actor with its weapon away and no
    /// fight is forgotten. The actor's graph hears each draw and sheathe, so it enters
    /// the weapon states a kill move starts from. A kill move keeps the weapon out to its
    /// end, because a sheathe would pull the graph out of the paired clip.
    func stepWeaponDraws(world: any CombatLoopWorld) {
        for key in Set(behaviors.keys).union(weaponDraws.keys).sorted() where key != .player {
            // A dead actor's graph plays its death; a sheathe would pull it out.
            guard world.combatActor(key: key)?.isDead != true else {
                weaponDraws[key] = nil
                continue
            }
            let wantsDrawn = activity(of: key) != .notFighting || world.combatIsInKillMove(key)
            var draw = weaponDraws[key] ?? NPCWeaponDraw()
            let before = draw.state
            draw.advance(
                wantsDrawn: wantsDrawn, by: Self.fixedStepSeconds,
                graphEquipping: draw.state == .drawing && world.combatGraphIsEquipping(key)
            )
            weaponDraws[key] = draw.state == .sheathed && !wantsDrawn ? nil : draw
            WeaponDrawGraph().tellGraph(
                of: key,
                drawGoing: (before, draw.state),
                world: world
            )
        }
    }
}

extension CombatLoopRuntime {
    /// Tells an actor's graph to draw or sheathe its weapon.
    struct WeaponDrawGraph {
        func tellGraph(
            of key: ReferenceKey, drawGoing change: (from: WeaponDrawState, to: WeaponDrawState),
            world: any CombatLoopWorld
        ) {
            switch change {
            case (.sheathed, .drawing):
                let right = world.combatWeapon(of: key)
                let left = world.combatLeftWeapon(of: key)?.handType
                    ?? (world.combatWearsShield(key) ? .shield : nil)
                world.writeCombatActorVariable(
                    right.handType.graphValue, named: CombatGraphNames.rightHandType, on: key
                )
                world.writeCombatActorVariable(
                    left?.graphValue ?? .int(0), named: CombatGraphNames.leftHandType,
                    on: key
                )
                world.raiseCombatEvent(CombatGraphNames.weapEquip, on: key)
            case (.drawn, .sheathing):
                world.raiseCombatEvent(CombatGraphNames.unequip, on: key)
            default:
                break
            }
        }
    }
}
