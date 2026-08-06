// Script-lifecycle emission for CellStreamer (issue #171).
//
// The streamer stays engine-level: it announces when a cell joins or leaves
// the live world and knows nothing about the Papyrus VM. GameViewController
// subscribes and forwards to `PapyrusWorldRuntime.attach`/`detach`, so every
// streaming test still runs without a VM.
//
// A scene with no `CellSceneLocation` (a door destination whose CELL identity
// failed to resolve) is not announced at all: the location is the key a
// subscriber files instances under, so there is nothing it could do with one.

import Foundation

extension CellStreamer {
    /// Announces a cell that is now part of the live world.
    ///
    /// - Parameter firstIntegration: false when the cell never left and its
    ///   scene was merely rebuilt, which is the signal not to re-fire load
    ///   events.
    func emitCellAttached(_ scene: CellScene, firstIntegration: Bool) {
        guard scene.location != nil else { return }
        onCellAttached?(scene, firstIntegration)
    }

    /// Announces a cell that left the live world. A nil scene or a scene
    /// without a location is a no-op for the announcement, so callers can pass
    /// an optional removal result directly.
    ///
    /// Cell-unload containment policy (issue #173): the player cannot stay
    /// inside a volume whose cell has gone, so every occupied volume this
    /// scene authored fires `leave` *first*, before the detach retires the
    /// scene's script instances. Retirement drops an instance's queued events,
    /// so a leave queued after the detach would be silently discarded; queuing
    /// it before is what gives a surviving (persistent) instance its cleanup.
    /// Trigger release is not gated on the location, because a volume has a
    /// `ReferenceKey` whether or not the CELL identity resolved.
    func emitCellDetached(_ scene: CellScene?) {
        guard let scene else { return }
        releaseTriggers(in: scene)
        guard let location = scene.location else { return }
        onCellDetached?(location)
    }
}
