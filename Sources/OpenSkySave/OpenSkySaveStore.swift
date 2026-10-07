// Named save slots over the encoder, decoder and atomic writer: a name becomes a URL,
// names that escape the saves directory are refused, and failures are typed. Not
// main-actor bound, so the CLI can use it. See docs/formats/opensky-save.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyScriptingInterface
import OpenSkyWorldState

/// Failure modes introduced by the slot layer, distinct from
/// `OpenSkySaveError`, which describes the container's own contents.
nonisolated public enum OpenSkySaveStoreError: Error, Equatable {
    /// The slot name is empty, over-long, or contains something that is not
    /// allowed in a file name here: a path separator, a leading dot, or a
    /// control character.
    case invalidSlotName(String, reason: String)
    /// No file exists for that slot in this store's directory.
    case slotNotFound(String)
    /// A plugin named by the load order could not be read or parsed while
    /// building a fingerprint. `message` is the underlying error's
    /// description.
    case unreadablePlugin(name: String, message: String)
}

/// A directory of named OpenSky saves.
nonisolated public struct OpenSkySaveStore: Sendable {
    /// Longest slot name accepted. Well under every filesystem's limit, and
    /// long enough for a date plus a description.
    public static let maximumSlotNameLength = 64

    /// Directory the slots live in. Created by whoever produced the URL;
    /// `defaultStore(fileManager:)` creates it.
    public let directory: URL

    /// `FileManager` is not `Sendable`, so the store reads `.default` at each call.
    private var fileManager: FileManager {
        .default
    }

    public init(directory: URL) {
        self.directory = directory
    }

    /// Store rooted at `OpenSkySaveIO.defaultSavesDirectory(fileManager:)`.
    public static func defaultStore(fileManager: FileManager = .default) throws
        -> OpenSkySaveStore
    {
        let directory = try OpenSkySaveIO.defaultSavesDirectory(fileManager: fileManager)
        return OpenSkySaveStore(directory: directory)
    }

    // MARK: - Slot names

    /// File URL of `slot` in this store.
    ///
    /// - Throws: `OpenSkySaveStoreError.invalidSlotName` when the name could
    ///   address something other than a plain file directly inside
    ///   `directory`.
    public func url(forSlot slot: String) throws -> URL {
        try Self.validate(slot: slot)
        return directory.appending(
            path: "\(slot).\(OpenSkySaveFormat.fileExtension)",
            directoryHint: .notDirectory
        )
    }

    /// Rejects anything that is not a plain file name. The check is a
    /// whitelist of failure reasons rather than a sanitizer: silently
    /// rewriting a user's slot name would make two different names collide.
    public static func validate(slot: String) throws {
        guard !slot.isEmpty else {
            throw OpenSkySaveStoreError.invalidSlotName(slot, reason: "the name is empty")
        }
        guard slot.count <= maximumSlotNameLength else {
            throw OpenSkySaveStoreError.invalidSlotName(
                slot,
                reason: "the name is longer than \(maximumSlotNameLength) characters"
            )
        }
        guard !slot.contains("/"), !slot.contains(":"), !slot.contains("\\") else {
            throw OpenSkySaveStoreError.invalidSlotName(
                slot,
                reason: "the name contains a path separator"
            )
        }
        guard !slot.hasPrefix(".") else {
            throw OpenSkySaveStoreError.invalidSlotName(
                slot,
                reason: "the name starts with a dot"
            )
        }
        guard slot.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else {
            throw OpenSkySaveStoreError.invalidSlotName(
                slot,
                reason: "the name contains a control character"
            )
        }
    }

    // MARK: - Saving and loading

    /// Encodes and atomically writes `snapshot` to `slot`. The key allocator travels as
    /// `nextGeneratedSequence`, so no second value can disagree with it.
    /// - Returns: the file that was written.
    @discardableResult
    public func save(
        snapshot: WorldStateSnapshot,
        fingerprint: [SavePluginFingerprint],
        metadata: SaveCreationMetadata,
        clock: GameClock? = nil,
        scripts: [PapyrusInstanceState] = [],
        timers: [PapyrusTimerState] = [],
        summary: SaveSummary? = nil,
        thumbnail: SaveThumbnail? = nil,
        playerPlace: SavePlayerPlace? = nil,
        toSlot slot: String
    ) throws -> URL {
        let destination = try url(forSlot: slot)
        let data = OpenSkySaveEncoder.encode(
            snapshot: snapshot,
            fingerprint: fingerprint,
            metadata: metadata,
            clock: clock,
            scripts: scripts,
            timers: timers,
            summary: summary,
            thumbnail: thumbnail,
            playerPlace: playerPlace
        )
        try OpenSkySaveIO.writeAtomically(data, to: destination)
        return destination
    }

    /// Reads and decodes `slot`, optionally checking it against the load order
    /// currently installed.
    ///
    /// Verification is opt-in because decoding must work with nothing but the
    /// file: an inspector on a machine with no game install passes nil, while
    /// the engine passes the fingerprint it built at startup.
    public func load(
        slot: String,
        verifyingAgainst current: [SavePluginFingerprint]? = nil
    ) throws -> OpenSkySaveFile {
        let source = try url(forSlot: slot)
        guard fileManager.fileExists(atPath: source.path(percentEncoded: false)) else {
            throw OpenSkySaveStoreError.slotNotFound(slot)
        }
        let file = try OpenSkySaveDecoder.decode(Data(contentsOf: source))
        if let current {
            try file.verifyFingerprint(against: current)
        }
        return file
    }

    /// Slot names present in this store, sorted, without the file extension.
    ///
    /// - Throws: whatever `FileManager` reports when the directory cannot be
    ///   listed. A missing directory is not an error: it means no save has
    ///   been written yet, so the result is empty.
    public func listSlots() throws -> [String] {
        guard fileManager.fileExists(atPath: directory.path(percentEncoded: false)) else {
            return []
        }
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return contents
            .filter { $0.pathExtension == OpenSkySaveFormat.fileExtension }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }
}

// MARK: - The save list

/// One file in the save list. `summary` is nil when the file cannot be read, so the
/// list still shows it and says why.
nonisolated public struct OpenSkySaveSlotListing: Equatable, Sendable {
    public let slot: String
    public let modified: Date
    public let summary: OpenSkySaveSummaryFile?
    public let error: String?
}

nonisolated extension OpenSkySaveStore {
    /// Every slot, newest first by file date, with its list chunks read.
    public func listings() throws -> [OpenSkySaveSlotListing] {
        try listSlots().map { slot in
            let url = try url(forSlot: slot)
            let modified = (try? fileManager.attributesOfItem(
                atPath: url.path(percentEncoded: false)
            )[.modificationDate] as? Date) ?? .distantPast
            do {
                let summary = try OpenSkySaveSummaryCodec.readSummary(Data(contentsOf: url))
                return OpenSkySaveSlotListing(
                    slot: slot, modified: modified, summary: summary, error: nil
                )
            } catch {
                return OpenSkySaveSlotListing(
                    slot: slot, modified: modified, summary: nil,
                    error: String(describing: error)
                )
            }
        }
        .sorted { ($0.modified, $1.slot) > ($1.modified, $0.slot) }
    }

    public func delete(slot: String) throws {
        let url = try url(forSlot: slot)
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw OpenSkySaveStoreError.slotNotFound(slot)
        }
        try fileManager.removeItem(at: url)
    }
}

// MARK: - Fingerprints

nonisolated extension OpenSkySaveStore {
    /// Load-order fingerprint of the plugins `root` resolves to, in load
    /// order.
    public static func fingerprint(
        forRoot root: GameDataRoot,
        location: PluginsTextLocation? = nil,
        fileManager: FileManager = .default
    ) throws -> [SavePluginFingerprint] {
        try fingerprint(
            forPlugins: PluginLoadOrder.resolve(
                root: root,
                location: location,
                fileManager: fileManager
            ).entries
        )
    }

    /// Fingerprint of a resolved load order; decodes only each TES4 record. Throws
    /// `OpenSkySaveStoreError.unreadablePlugin` for the first unreadable plugin, because
    /// a partial fingerprint would verify against nothing.
    public static func fingerprint(
        forPlugins entries: [PluginLoadOrder.Entry]
    ) throws -> [SavePluginFingerprint] {
        try entries.map { entry in
            do {
                let stats = try ESMFile(url: entry.url).pluginHeader().stats
                return SavePluginFingerprint(pluginName: entry.name, stats: stats)
            } catch {
                throw OpenSkySaveStoreError.unreadablePlugin(
                    name: entry.name,
                    message: String(describing: error)
                )
            }
        }
    }
}
