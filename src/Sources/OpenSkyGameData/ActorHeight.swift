// An actor's height: its own `NPC_` `NAM6` share times its race's height for its sex
// (`RACE` `DATA`). It scales the drawn model, the walk speeds, and the collision shape.
// See docs/engine/actor-resolution.md#height.

import OpenSkyFormatsCore
public import OpenSkyFormatsESM

nonisolated public enum ActorHeight {
    /// 1 when either value is missing, zero, or not finite, so a bad record draws at its
    /// reference scale.
    public static func scale(npcHeight: Float, race: Race?, isFemale: Bool) -> Float {
        let own = npcHeight > 0 && npcHeight.isFinite ? npcHeight : 1
        guard let heights = race?.details.properties?.height else { return own }
        let raceHeight = isFemale ? heights.female : heights.male
        return raceHeight > 0 && raceHeight.isFinite ? own * raceHeight : own
    }
}

extension ActorIdentityRecords {
    /// The height after `useTraits` inheritance, times the race's height.
    public func heightScale(ofBase base: FormID, roll: LeveledRoll? = nil) -> Float {
        guard let resolved = attempt({ try templates.rolling(roll).resolve(base: base) }) else {
            return 1
        }
        let race = resolved.race.value.flatMap { races[$0.rawValue] }
        return ActorHeight.scale(
            npcHeight: resolved.height, race: race, isFemale: resolved.isFemale.value
        )
    }
}
