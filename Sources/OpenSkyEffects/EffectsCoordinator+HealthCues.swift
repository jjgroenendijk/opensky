// The low-health cues: the pulse modifier starts here, and the heartbeat change goes back
// to the caller, which owns the sound (docs/rendering/image-space.md#low-health).

public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyRenderCore
public import OpenSkyWorldInterface

extension EffectsCoordinator {
    /// Reads the player's health share this frame and starts a pulse when one is due.
    /// Returns the heartbeat change; `seconds` is 0 while the world is paused.
    public func stepHealthCues(
        share: Float,
        seconds: Float,
        heartbeatPlaying: Bool,
        imageSpace: inout ImageSpaceState
    ) -> HeartbeatChange? {
        guard seconds > 0 else { return nil }
        let change = healthCues.healthChanged(share: share, heartbeatPlaying: heartbeatPlaying)
        if
            let strength = healthCues.advance(seconds),
            let key = records.lowHealthModifier,
            let adapter = records.imageSpaceAdapters.record(key)
        {
            imageSpace.modifiers.start(
                adapter.record, key: key, strength: strength,
                strengthLimit: PlayerHealthCues.strongestPulse, stacks: true
            )
        }
        return change
    }

    /// The load-order sound of `heartbeat`, for the sound director.
    public func heartbeatSound(_ heartbeat: Heartbeat) -> FormID? {
        let key = heartbeat == .slow ? records.slowHeartbeat : records.fastHeartbeat
        return key.flatMap(records.loadOrderFormID)
    }
}
