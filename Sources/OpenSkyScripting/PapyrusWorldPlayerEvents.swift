// Events the player's scripts get from the session rather than from a reference: a save
// that loaded, and a move into another location. Alias scripts on the player share the
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

    private func locationValue(_ location: ResolvedFormID?) -> PapyrusValue {
        location.map { .object(objectHandle(for: ReferenceKey(resolved: $0))) } ?? .none
    }
}
