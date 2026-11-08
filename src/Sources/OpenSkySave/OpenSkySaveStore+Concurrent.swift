// The save file work the app runs off the main actor. Each function reads or writes
// files on the concurrent pool; see docs/decisions/concurrency.md.

import Foundation
import OpenSkyGameData
public import OpenSkySaveInterface
import OpenSkyScriptingInterface
import OpenSkyWorldState

nonisolated extension OpenSkySaveStore {
    /// Creates the saves directory when it is missing.
    @concurrent
    public static func openDefault() async throws -> OpenSkySaveStore {
        try defaultStore()
    }

    /// Opens the header of every installed plugin.
    @concurrent
    public static func installedFingerprint() async throws -> [SavePluginFingerprint] {
        try fingerprint(forRoot: GameDataLocator.locate())
    }

    @concurrent
    public func write(
        _ contents: OpenSkySaveContents, fingerprint: [SavePluginFingerprint], toSlot slot: String
    ) async throws {
        try save(
            snapshot: contents.snapshot,
            fingerprint: fingerprint,
            metadata: contents.metadata,
            clock: contents.clock,
            scripts: contents.scripts,
            timers: contents.timers,
            summary: contents.summary,
            thumbnail: contents.thumbnail,
            playerPlace: contents.playerPlace,
            toSlot: slot
        )
    }

    @concurrent
    public func read(
        slot: String, verifyingAgainst current: [SavePluginFingerprint]?
    ) async throws -> OpenSkySaveFile {
        try load(slot: slot, verifyingAgainst: current)
    }

    @concurrent
    public func readListings() async throws -> [OpenSkySaveSlotListing] {
        try listings()
    }

    @concurrent
    public func readSlots() async throws -> [String] {
        try listSlots()
    }

    @concurrent
    public func remove(slot: String) async throws {
        try delete(slot: slot)
    }
}
