// Decoded contents of an OpenSky native save (issue #161).
//
// Load-order verification is deliberately not part of decoding. Decoding must
// work with nothing but the file — an inspector, a test, or a repair tool can
// read a save on a machine with no game install at all — while verification
// needs the plugins that are currently installed. Keeping them apart also lets
// the app show what a save contains before it tells the user why it cannot be
// loaded.

import Foundation

nonisolated struct OpenSkySaveFile: Equatable, Sendable {
    /// Layout version the file declared.
    let formatVersion: UInt32
    let metadata: SaveCreationMetadata
    /// Load order the save was written against, in load order.
    let fingerprint: [SavePluginFingerprint]
    /// World state at save time. Its `sequence` is 0: the journal position is
    /// session-local bookkeeping and is not saved.
    let snapshot: WorldStateSnapshot
    /// Allocator resumed at the saved position, so a restored session hands
    /// out generated keys that cannot collide with saved ones.
    let allocator: GeneratedReferenceAllocator
    /// Game clock at save time (issue #164), nil when the file carries no
    /// `CLOK` chunk — a pre-clock save — which restores the vanilla-start
    /// clock.
    let clock: GameClock?
    /// Papyrus script instance state at save time (issue #171), empty when the
    /// file carries no `PSCR` chunk — a pre-script save, or a session that ran
    /// no VM — which restores scripts at their compiled defaults.
    let scripts: [PapyrusInstanceState]
    /// Pending Papyrus update timers at save time (issue #277), empty when the
    /// file carries no `PTMR` chunk — a pre-timer save, or a session in which
    /// no persistent instance had a timer armed — which restores a world where
    /// no script has a pending `OnUpdate`.
    let timers: [PapyrusTimerState]

    init(
        formatVersion: UInt32,
        metadata: SaveCreationMetadata,
        fingerprint: [SavePluginFingerprint],
        snapshot: WorldStateSnapshot,
        allocator: GeneratedReferenceAllocator,
        clock: GameClock? = nil,
        scripts: [PapyrusInstanceState] = [],
        timers: [PapyrusTimerState] = []
    ) {
        self.formatVersion = formatVersion
        self.metadata = metadata
        self.fingerprint = fingerprint
        self.snapshot = snapshot
        self.allocator = allocator
        self.clock = clock
        self.scripts = scripts
        self.timers = timers
    }

    /// Checks the saved load order against the one currently installed.
    ///
    /// Order matters: plugin-defined `ReferenceKey`s are name-based and so
    /// survive reordering, but records, masters and object IDs do not, so a
    /// reordered load order is reported as a mismatch rather than accepted.
    /// File-name case is ignored, matching how plugin names are compared
    /// everywhere else in the engine.
    ///
    /// - Throws: `OpenSkySaveError.fingerprintMismatch` naming the first
    ///   difference.
    func verifyFingerprint(against current: [SavePluginFingerprint]) throws {
        for index in 0 ..< max(fingerprint.count, current.count) {
            try Self.compare(
                saved: Self.element(fingerprint, at: index),
                installed: Self.element(current, at: index),
                at: index
            )
        }
    }

    private static func element(
        _ list: [SavePluginFingerprint],
        at index: Int
    ) -> SavePluginFingerprint? {
        index < list.count ? list[index] : nil
    }

    private static func compare(
        saved: SavePluginFingerprint?,
        installed: SavePluginFingerprint?,
        at index: Int
    ) throws {
        switch (saved, installed) {
        case let (.some(saved), .none):
            throw OpenSkySaveError.fingerprintMismatch(
                reason: "plugin '\(saved.name)' was loaded when the save was written "
                    + "but is not loaded now"
            )
        case let (.none, .some(installed)):
            throw OpenSkySaveError.fingerprintMismatch(
                reason: "plugin '\(installed.name)' is loaded now but was not loaded "
                    + "when the save was written"
            )
        case let (.some(saved), .some(installed)):
            guard saved.namesSamePlugin(as: installed) else {
                throw OpenSkySaveError.fingerprintMismatch(
                    reason: "load order changed at position \(index): the save expects "
                        + "'\(saved.name)' where '\(installed.name)' is loaded now"
                )
            }
            guard saved.hasSameStats(as: installed) else {
                throw OpenSkySaveError.fingerprintMismatch(
                    reason: "plugin '\(saved.name)' changed since the save was written"
                )
            }
        case (.none, .none):
            break
        }
    }
}
