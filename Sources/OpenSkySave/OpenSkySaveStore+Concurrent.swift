// The save file work the app runs off the main actor. Each function reads or writes
// files on the concurrent pool; see docs/decisions/concurrency.md.

import Foundation
import OpenSkyGameData
import OpenSkyScriptingInterface
import OpenSkyWorldState

/// Everything one save writes, taken on the main actor in one frame so it is consistent.
nonisolated public struct OpenSkySaveContents: Sendable {
    public let snapshot: WorldStateSnapshot
    public let metadata: SaveCreationMetadata
    public let clock: GameClock?
    public let scripts: [PapyrusInstanceState]
    public let timers: [PapyrusTimerState]
    public let summary: SaveSummary?
    public let thumbnail: SaveThumbnail?
    public let playerPlace: SavePlayerPlace?

    public init(
        snapshot: WorldStateSnapshot,
        metadata: SaveCreationMetadata,
        clock: GameClock? = nil,
        scripts: [PapyrusInstanceState] = [],
        timers: [PapyrusTimerState] = [],
        summary: SaveSummary? = nil,
        thumbnail: SaveThumbnail? = nil,
        playerPlace: SavePlayerPlace? = nil
    ) {
        self.snapshot = snapshot
        self.metadata = metadata
        self.clock = clock
        self.scripts = scripts
        self.timers = timers
        self.summary = summary
        self.thumbnail = thumbnail
        self.playerPlace = playerPlace
    }
}

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
