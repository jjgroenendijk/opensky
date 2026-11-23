// Each NPC's weapon draw state: drawing when its fight starts, sheathing when it ends.
// See docs/engine/condition-functions-world.md#combat-actions.

public import OpenSkyActorsInterface
public import OpenSkyFormatsESM

extension CombatLoopRuntime {
    /// Where the weapon of the NPC `key` is. Nil for the player, whose melee state
    /// tracks its own draw.
    public func drawState(of key: ReferenceKey) -> WeaponDrawState? {
        key == .player ? nil : weaponDraws[key]?.state ?? .sheathed
    }

    /// One fixed step of every tracked draw. An actor with its weapon away and no
    /// fight is forgotten.
    func stepWeaponDraws() {
        for key in Set(behaviors.keys).union(weaponDraws.keys).sorted() where key != .player {
            let wantsDrawn = activity(of: key) != .notFighting
            var draw = weaponDraws[key] ?? NPCWeaponDraw()
            draw.advance(wantsDrawn: wantsDrawn, by: Self.fixedStepSeconds)
            weaponDraws[key] = draw.state == .sheathed && !wantsDrawn ? nil : draw
        }
    }
}
