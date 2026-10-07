// Decoded contents of an OpenSky save. Load-order verification is separate, so a file
// decodes without an install and the app can show a save before saying why it cannot load.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface
import OpenSkyWorldState

nonisolated public struct OpenSkySaveFile: Equatable, Sendable {
    /// Layout version the file declared.
    public let formatVersion: UInt32
    public let metadata: SaveCreationMetadata
    /// Load order the save was written against, in load order.
    public let fingerprint: [SavePluginFingerprint]
    /// World state at save time. Its `sequence` is 0: the journal position is
    /// session-local bookkeeping and is not saved.
    public let snapshot: WorldStateSnapshot
    /// Allocator resumed at the saved position, so a restored session hands
    /// out generated keys that cannot collide with saved ones.
    public let allocator: GeneratedReferenceAllocator
    /// Game clock at save time; nil without a `CLOK` chunk, which means the vanilla start.
    public let clock: GameClock?
    /// Papyrus script state at save time; empty without a `PSCR` chunk, so scripts start
    /// at their compiled defaults.
    public let scripts: [PapyrusInstanceState]
    /// Pending Papyrus update timers at save time; empty without a `PTMR` chunk, so no
    /// `OnUpdate` is pending.
    public let timers: [PapyrusTimerState]
    /// Where the player stood; nil without a `PLOC` chunk.
    public let playerPlace: SavePlayerPlace?

    public init(
        formatVersion: UInt32,
        metadata: SaveCreationMetadata,
        fingerprint: [SavePluginFingerprint],
        snapshot: WorldStateSnapshot,
        allocator: GeneratedReferenceAllocator,
        clock: GameClock? = nil,
        scripts: [PapyrusInstanceState] = [],
        timers: [PapyrusTimerState] = [],
        playerPlace: SavePlayerPlace? = nil
    ) {
        self.formatVersion = formatVersion
        self.metadata = metadata
        self.fingerprint = fingerprint
        self.snapshot = snapshot
        self.allocator = allocator
        self.clock = clock
        self.scripts = scripts
        self.timers = timers
        self.playerPlace = playerPlace
    }

    /// Checks the saved load order against the installed one. A reorder is a mismatch,
    /// because records and object IDs do not survive it. Case is ignored.
    /// - Throws: `OpenSkySaveError.fingerprintMismatch` naming the first difference.
    public func verifyFingerprint(against current: [SavePluginFingerprint]) throws {
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
