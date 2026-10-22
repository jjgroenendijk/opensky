// A sandbox moves its actor on when an activity's time runs out. The actor leaves its
// idle marker, and takes a marker away from it next. See docs/engine/idle-runtime.md.

import OpenSkyFormatsESM

extension IdleCoordinator {
    /// Ends the actor's idle and frees its marker. Its next marker is another one.
    public func leaveMarker(_ actor: ReferenceKey) {
        guard let marker = sessions[actor]?.marker else { return }
        endIdle(of: actor)
        sessions[actor] = nil
        previousMarkers[actor] = marker
    }

    /// After an activity away from markers, the last marker may be taken again.
    public func allowPreviousMarker(_ actor: ReferenceKey) {
        previousMarkers[actor] = nil
    }
}
