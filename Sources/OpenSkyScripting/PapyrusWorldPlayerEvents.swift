// Events actor scripts get from the session rather than from a reference: a save that
// loaded, a move into another location, the end of fast travel, furniture use, a spell
// cast, a bow shot, and a vampire's feeding. Alias scripts on the player share the
// player's key, so they get them too.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusWorldRuntime {
    /// Queues `OnPlayerLoadGame()` on each script of the player. Returns the count.
    @discardableResult
    public func queuePlayerLoadGame() -> Int {
        queueActorEvent(PapyrusEngineEvents.onPlayerLoadGame, on: .player, arguments: [])
    }

    /// Queues `OnLocationChange(akOldLoc, akNewLoc)` on each script of `actor`. A nil
    /// location is the wilderness, which scripts see as `None`. Returns the count.
    @discardableResult
    public func queueLocationChange(
        actor: ReferenceKey, from old: ResolvedFormID?, to new: ResolvedFormID?
    ) -> Int {
        queueActorEvent(
            PapyrusEngineEvents.onLocationChange,
            on: actor,
            arguments: [locationValue(old), locationValue(new)]
        )
    }

    /// `OnPlayerFastTravelEnd(float afTravelGameTimeHours)` on the player's scripts.
    @discardableResult
    public func queuePlayerFastTravelEnd(gameHours: Float) -> Int {
        queueActorEvent(
            PapyrusEngineEvents.onPlayerFastTravelEnd, on: .player, arguments: [.float(gameHours)]
        )
    }

    /// `OnSit(ObjectReference akFurniture)` or `OnGetUp(ObjectReference akFurniture)` on
    /// the actor's scripts.
    @discardableResult
    public func queueFurnitureEvent(
        sitting: Bool, actor: ReferenceKey, furniture: ReferenceKey
    ) -> Int {
        queueActorEvent(
            sitting ? PapyrusEngineEvents.onSit : PapyrusEngineEvents.onGetUp,
            on: actor,
            arguments: [.object(objectHandle(for: furniture))]
        )
    }

    /// `OnSpellCast(Form akSpell)` on the caster's scripts.
    @discardableResult
    public func queueSpellCast(_ spell: ReferenceKey, by caster: ReferenceKey) -> Int {
        queueActorEvent(
            PapyrusEngineEvents.onSpellCast, on: caster,
            arguments: [.object(objectHandle(for: spell))]
        )
    }

    /// `OnPlayerBowShot(Weapon akWeapon, Ammo akAmmo, float afPower, bool abSunGazing)` on the
    /// player's scripts (<https://ck.uesp.net/wiki/OnPlayerBowShot_-_Actor>).
    @discardableResult
    public func queuePlayerBowShot(
        weapon: FormID?, ammunition: FormID?, power: Float, sunGazing: Bool
    ) -> Int {
        queueActorEvent(
            PapyrusEngineEvents.onPlayerBowShot, on: .player,
            arguments: [
                formValue(weapon), formValue(ammunition), .float(power), .boolean(sunGazing)
            ]
        )
    }

    /// `OnVampireFeed(Actor akTarget)` on the feeder's scripts.
    @discardableResult
    public func queueVampireFeed(feeder: ReferenceKey, target: ReferenceKey) -> Int {
        queueActorEvent(
            PapyrusEngineEvents.onVampireFeed, on: feeder,
            arguments: [.object(objectHandle(for: target))]
        )
    }

    private func locationValue(_ location: ResolvedFormID?) -> PapyrusValue {
        location.map { .object(objectHandle(for: ReferenceKey(resolved: $0))) } ?? .none
    }
}
