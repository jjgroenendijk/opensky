// Named save slots on top of the OpenSky native save container (issue #162,
// roadmap item 10.1.5).
//
// The encoder, decoder and atomic writer from issue #161 each do one thing and
// none of them knows where a save lives or what it is called. This type is the
// small amount of glue between them and a user who thinks in slot names: it
// turns a name into a URL, refuses names that would escape the saves
// directory, and reports every failure as a typed error so a panel can show
// what went wrong without a crash.
//
// Nothing here is main-actor bound. A save is a value plus a file, so the CLI
// and a background task can use this exactly like the app does.
//
// Documented in docs/formats/opensky-save.md.

import Foundation

/// Failure modes introduced by the slot layer, distinct from
/// `OpenSkySaveError`, which describes the container's own contents.
nonisolated enum OpenSkySaveStoreError: Error, Equatable {
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
nonisolated struct OpenSkySaveStore {
    /// Longest slot name accepted. Well under every filesystem's limit, and
    /// long enough for a date plus a description.
    static let maximumSlotNameLength = 64

    /// Directory the slots live in. Created by whoever produced the URL;
    /// `defaultStore(fileManager:)` creates it.
    let directory: URL
    private let fileManager: FileManager

    init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    /// Store rooted at `OpenSkySaveIO.defaultSavesDirectory(fileManager:)`.
    static func defaultStore(fileManager: FileManager = .default) throws -> OpenSkySaveStore {
        let directory = try OpenSkySaveIO.defaultSavesDirectory(fileManager: fileManager)
        return OpenSkySaveStore(directory: directory, fileManager: fileManager)
    }

    // MARK: - Slot names

    /// File URL of `slot` in this store.
    ///
    /// - Throws: `OpenSkySaveStoreError.invalidSlotName` when the name could
    ///   address something other than a plain file directly inside
    ///   `directory`.
    func url(forSlot slot: String) throws -> URL {
        try Self.validate(slot: slot)
        return directory.appending(
            path: "\(slot).\(OpenSkySaveFormat.fileExtension)",
            directoryHint: .notDirectory
        )
    }

    /// Rejects anything that is not a plain file name. The check is a
    /// whitelist of failure reasons rather than a sanitizer: silently
    /// rewriting a user's slot name would make two different names collide.
    static func validate(slot: String) throws {
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

    /// Encodes and atomically writes `snapshot` to `slot`.
    ///
    /// The generated-key allocator is not a separate parameter: its entire
    /// state is one number, the snapshot already carries it as
    /// `nextGeneratedSequence`, and the decoder rebuilds
    /// `OpenSkySaveFile.allocator` from that same number. Passing an allocator
    /// alongside a snapshot would make it possible to save two positions that
    /// disagree.
    ///
    /// - Returns: the file that was written.
    @discardableResult
    func save(
        snapshot: WorldStateSnapshot,
        fingerprint: [SavePluginFingerprint],
        metadata: SaveCreationMetadata,
        clock: GameClock? = nil,
        scripts: [PapyrusInstanceState] = [],
        toSlot slot: String
    ) throws -> URL {
        let destination = try url(forSlot: slot)
        let data = OpenSkySaveEncoder.encode(
            snapshot: snapshot,
            fingerprint: fingerprint,
            metadata: metadata,
            clock: clock,
            scripts: scripts
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
    func load(
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
    func listSlots() throws -> [String] {
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

// MARK: - Fingerprints

nonisolated extension OpenSkySaveStore {
    /// Load-order fingerprint of the plugins `root` resolves to, in load
    /// order.
    static func fingerprint(
        forRoot root: GameDataRoot,
        pluginsTextURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> [SavePluginFingerprint] {
        try fingerprint(
            forPlugins: PluginLoadOrder.resolve(
                root: root,
                pluginsTextURL: pluginsTextURL,
                fileManager: fileManager
            )
        )
    }

    /// Fingerprint of an already-resolved load order.
    ///
    /// Only the TES4 record of each plugin is decoded, which is one small
    /// record at the head of a memory-mapped file, so fingerprinting a full
    /// load order costs no more than opening it.
    ///
    /// - Throws: `OpenSkySaveStoreError.unreadablePlugin` naming the first
    ///   plugin that could not be read or parsed. A save written against a
    ///   load order that was only partly readable would verify against
    ///   nothing, so this fails rather than skipping the entry.
    static func fingerprint(
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
