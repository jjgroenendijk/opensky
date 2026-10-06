// Reader for the OpenSky save container: header, load-order fingerprint, chunks.
// An unknown chunk is skipped, so a newer save still loads. An unknown component
// kind inside a known chunk throws, because losing a component corrupts the world.

import Foundation
import OpenSkyFormatsESM
import OpenSkyWorldState

nonisolated public enum OpenSkySaveDecoder: Sendable {
    public static func decode(_ data: Data) throws -> OpenSkySaveFile {
        var reader = SaveReader(data)
        let magic = try reader.bytes(OpenSkySaveFormat.magic.count, "magic")
        guard magic == OpenSkySaveFormat.magic else {
            throw OpenSkySaveError.badMagic
        }
        let version = try reader.uint32("format version")
        guard version == OpenSkySaveFormat.currentVersion else {
            throw OpenSkySaveError.unsupportedVersion(found: version)
        }
        let metadata = try decodeMetadata(&reader)
        let fingerprint = try decodeFingerprint(&reader)
        let body = try decodeChunks(&reader)
        return OpenSkySaveFile(
            formatVersion: version,
            metadata: metadata,
            fingerprint: fingerprint,
            snapshot: WorldStateSnapshot(
                entries: mergedEntries(of: body),
                nextGeneratedSequence: body.nextGeneratedSequence,
                globals: body.globals,
                sequence: 0
            ),
            allocator: GeneratedReferenceAllocator(nextSequence: body.nextGeneratedSequence),
            clock: body.clock,
            scripts: body.scripts,
            timers: body.timers
        )
    }

    /// The `RDLT` entries with every side-chunk laid back over them. Each merge
    /// fills its own component slot, so only the commented steps depend on order.
    private static func mergedEntries(of body: Body) -> [WorldStateSnapshotEntry] {
        // A repeated `RDLT` key keeps its last entry, as every merge below does.
        let deltas = OpenSkySaveDeltaMerge.sorted(OpenSkySaveDeltaMerge.index(body.entries))
        var entries = OpenSkySaveDeltaMerge.merge(body.inventories, into: deltas)
        entries = OpenSkySaveDeltaMerge.merge(body.spawns, into: entries)
        entries = OpenSkySaveDeltaMerge.merge(body.quests, into: entries)
        entries = OpenSkySaveDeltaMerge.merge(body.questAliases, into: entries)
        entries = OpenSkySaveQuestDecoder.mergeLocationAliases(
            body.questLocationAliases,
            into: entries
        )
        // `AVOV` lays onto the `AVAL` entries before those reach the deltas, so
        // an actor's primaries and its general table arrive as one component.
        let actorValues = OpenSkySaveActorValueDecoder.mergeOverrides(
            body.actorValueOverrides,
            into: body.actorValues
        )
        entries = OpenSkySaveDeltaMerge.merge(actorValues, into: entries)
        entries = OpenSkySaveDeltaMerge.merge(body.deaths, into: entries)
        entries = OpenSkySaveDeltaMerge.merge(body.combatStates, into: entries)
        entries = OpenSkySaveDeltaMerge.merge(body.dialogue, into: entries)
        entries = OpenSkySaveDeltaMerge.merge(body.activeEffects, into: entries)
        entries = OpenSkySaveDeltaMerge.merge(body.spellbooks, into: entries)
        entries = OpenSkySaveDeltaMerge.merge(body.enchantedItems, into: entries)
        entries = OpenSkySaveDeltaMerge.merge(body.perks, into: entries)
        entries = OpenSkySaveDeltaMerge.merge(body.factions, into: entries)
        entries = OpenSkySaveDeltaMerge.merge(body.relationships, into: entries)
        entries = OpenSkySaveDeltaMerge.merge(body.playerProgress, into: entries)
        // `CRVG` splits the `CRIM` totals before those reach the deltas, the
        // way `AVOV` lays onto `AVAL`.
        let ledgers = OpenSkySaveCrimeDecoder.splittingViolent(
            body.violentCrimeGold,
            in: body.crimeLedgers
        )
        entries = OpenSkySaveDeltaMerge.merge(ledgers, into: entries)
        entries = OpenSkySaveDeltaMerge.merge(body.harvests, into: entries)
        // After `HRVS`: a day only times a harvest `HRVS` already restored.
        let harvested = Set(body.harvests.map(\.key))
        entries = OpenSkySaveDeltaMerge.merge(
            body.harvestDays.filter { harvested.contains($0.key) },
            into: entries
        )
        entries = OpenSkySaveDeltaMerge.merge(body.locks, into: entries)
        entries = OpenSkySaveDeltaMerge.merge(body.scenes, into: entries)
        entries = OpenSkySaveDeltaMerge.merge(body.storyManagerQuests, into: entries)
        entries = OpenSkySaveDeltaMerge.merge(body.dialogueBranches, into: entries)
        entries = OpenSkySaveDeltaMerge.merge(body.helpMessages, into: entries)
        entries = OpenSkySaveDeltaMerge.merge(body.identities, into: entries)
        entries = OpenSkySaveDeltaMerge.merge(body.markers, into: entries)
        entries = OpenSkySaveDeltaMerge.merge(body.fog, into: entries)
        // After `INVN`: `STOL` re-flags stacks the inventory merge has already
        // restored, so it cannot run before those totals are in place.
        return OpenSkySaveCrimeDecoder.mergeStolen(body.stolenGoods, into: entries)
    }

    // MARK: - Header

    /// Metadata is length-delimited so unknown trailing fields a newer build
    /// added are skipped rather than mistaken for the fingerprint.
    static func decodeMetadata(_ reader: inout SaveReader) throws -> SaveCreationMetadata {
        let length = try Int(reader.uint32("metadata length"))
        let block = try reader.bytes(length, "metadata")
        var blockReader = SaveReader(block)
        let timestamp = try blockReader.uint64("metadata creation timestamp")
        let appVersion = try blockReader.string("metadata app version")
        return SaveCreationMetadata(creationTimestamp: timestamp, appVersion: appVersion)
    }

    static func decodeFingerprint(
        _ reader: inout SaveReader
    ) throws -> [SavePluginFingerprint] {
        let count = try reader.uint32("fingerprint plugin count")
        try validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumFingerprintEntrySize,
            remaining: reader.bytesRemaining,
            chunk: "fingerprint"
        )
        var plugins: [SavePluginFingerprint] = []
        plugins.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            let name = try reader.string("plugin name")
            let hedrVersion = try Float(bitPattern: reader.uint32("plugin HEDR version"))
            let recordCount = try Int32(bitPattern: reader.uint32("plugin record count"))
            let nextObjectID = try reader.uint32("plugin next object ID")
            plugins.append(SavePluginFingerprint(
                name: name,
                hedrVersion: hedrVersion,
                recordCount: recordCount,
                nextObjectID: nextObjectID
            ))
        }
        return plugins
    }

    // MARK: - Chunks

    private static func decodeChunks(_ reader: inout SaveReader) throws -> Body {
        var body = Body()
        while !reader.isAtEnd {
            let tag = try tagName(reader.bytes(4, "chunk tag"))
            let length = try Int(reader.uint32("chunk length"))
            guard length <= reader.bytesRemaining else {
                throw OpenSkySaveError.chunkBoundsViolation(tag: tag)
            }
            let payload = try reader.bytes(length, "chunk payload")
            try apply(tag: tag, payload: payload, to: &body)
        }
        return body
    }

    /// Printable name for a four-byte chunk tag.
    ///
    /// A tag that is not valid UTF-8 is reported as hex rather than dropped:
    /// an unreadable tag is exactly the corruption whose error message needs to
    /// say what it saw, and an unknown tag is skipped by its length anyway.
    static func tagName(_ bytes: Data) -> String {
        String(bytes: bytes, encoding: .utf8) ?? bytes.map { String(format: "%02X", $0) }.joined()
    }

    private static func apply(tag: String, payload: Data, to body: inout Body) throws {
        switch tag {
        case OpenSkySaveFormat.ChunkTag.allocator:
            guard payload.count == MemoryLayout<UInt64>.size else {
                throw OpenSkySaveError.invalidValue(
                    context: "GALC payload is \(payload.count) bytes, expected 8"
                )
            }
            var payloadReader = SaveReader(payload)
            body.nextGeneratedSequence = try payloadReader.uint64("GALC next generated sequence")
        case OpenSkySaveFormat.ChunkTag.referenceDeltas:
            body.entries = try OpenSkySaveEntryDecoder.decodeEntries(payload)
        case OpenSkySaveFormat.ChunkTag.globalValues:
            body.globals = try OpenSkySaveEntryDecoder.decodeGlobals(payload)
        case OpenSkySaveFormat.ChunkTag.clock:
            body.clock = try decodeClock(payload)
        case OpenSkySaveFormat.ChunkTag.papyrusScripts:
            body.scripts = try OpenSkySaveScriptDecoder.decodeScripts(payload)
        case OpenSkySaveFormat.ChunkTag.papyrusTimers:
            body.timers = try OpenSkySaveTimerDecoder.decodeTimers(payload)
        default:
            // The gameplay-state chunks, in their own pass: the switch above is
            // at the strict cyclomatic-complexity limit, and a new chunk tag
            // belongs beside its siblings rather than pushing this one over.
            try applyGameplay(tag: tag, payload: payload, to: &body)
        }
    }

    /// The per-subsystem chunks that hang off `WorldStateSnapshot` entries.
    /// An unknown tag falls through here and is skipped by its declared length,
    /// which is the whole tolerance rule the chunk stream exists to provide.
    private static func applyGameplay(
        tag: String,
        payload: Data,
        to body: inout Body
    ) throws {
        switch tag {
        case OpenSkySaveFormat.ChunkTag.inventories:
            body.inventories = try OpenSkySaveInventoryDecoder.decodeInventories(payload)
        case OpenSkySaveFormat.ChunkTag.spawnedReferences:
            body.spawns = try OpenSkySaveSpawnDecoder.decodeSpawns(payload)
        case OpenSkySaveFormat.ChunkTag.questStates:
            body.quests = try OpenSkySaveQuestDecoder.decodeQuestStates(payload)
        case OpenSkySaveFormat.ChunkTag.questAliases:
            body.questAliases = try OpenSkySaveQuestDecoder.decodeQuestAliases(payload)
        case OpenSkySaveFormat.ChunkTag.questLocationAliases:
            body.questLocationAliases = try OpenSkySaveQuestDecoder
                .decodeQuestLocationAliases(payload)
        case OpenSkySaveFormat.ChunkTag.actorValues:
            body.actorValues = try OpenSkySaveActorValueDecoder.decodeActorValues(payload)
        case OpenSkySaveFormat.ChunkTag.actorValueOverrides:
            body.actorValueOverrides = try OpenSkySaveActorValueDecoder
                .decodeActorValueOverrides(payload)
        default:
            // The actor-side chunks continue in a second pass, which is what
            // keeps this switch inside the strict cyclomatic-complexity cap.
            try applyActorGameplay(tag: tag, payload: payload, to: &body)
        }
    }

    /// The half of the gameplay chunks keyed by an actor rather than by a
    /// quest, a container or a placement. Split from `applyGameplay` only for
    /// the complexity cap; the tolerance rule is the same, and an unknown tag
    /// reaching here is skipped by its declared length.
    private static func applyActorGameplay(
        tag: String,
        payload: Data,
        to body: inout Body
    ) throws {
        switch tag {
        case OpenSkySaveFormat.ChunkTag.deaths:
            body.deaths = try OpenSkySaveDeathDecoder.decodeDeaths(payload)
        case OpenSkySaveFormat.ChunkTag.combatStates:
            body.combatStates = try OpenSkySaveCombatDecoder.decodeCombatStates(payload)
        case OpenSkySaveFormat.ChunkTag.dialogueStates:
            body.dialogue = try OpenSkySaveDialogueDecoder.decodeDialogueStates(payload)
        case OpenSkySaveFormat.ChunkTag.activeEffects:
            body.activeEffects = try OpenSkySaveActiveEffectDecoder.decodeActiveEffects(payload)
        case OpenSkySaveFormat.ChunkTag.spellbooks:
            body.spellbooks = try OpenSkySaveSpellbookDecoder.decodeSpellbooks(payload)
        case OpenSkySaveFormat.ChunkTag.enchantedItems:
            body.enchantedItems = try OpenSkySaveEnchantedItemDecoder
                .decodeEnchantedItems(payload)
        case OpenSkySaveFormat.ChunkTag.perks:
            body.perks = try OpenSkySavePerkDecoder.decodePerks(payload)
        default:
            // Split again for the complexity cap, on the same rule.
            try applySocialGameplay(tag: tag, payload: payload, to: &body)
        }
    }

    /// The social and progression half: who an actor sides with, what two actors
    /// are to each other, how far the player has come, and what they owe for.
    /// Split from `applyActorGameplay` only for the complexity cap.
    private static func applySocialGameplay(
        tag: String,
        payload: Data,
        to body: inout Body
    ) throws {
        switch tag {
        case OpenSkySaveFormat.ChunkTag.factions:
            body.factions = try OpenSkySaveFactionDecoder
                .decodeFactionMemberships(payload)
        case OpenSkySaveFormat.ChunkTag.relationships:
            body.relationships = try OpenSkySaveRelationshipDecoder
                .decodeRelationshipRanks(payload)
        case OpenSkySaveFormat.ChunkTag.playerProgress:
            body.playerProgress = try OpenSkySaveProgressDecoder
                .decodePlayerProgress(payload)
        case OpenSkySaveFormat.ChunkTag.crimeLedgers:
            body.crimeLedgers = try OpenSkySaveCrimeDecoder.decodeCrimeLedgers(payload)
        case OpenSkySaveFormat.ChunkTag.stolenGoods:
            body.stolenGoods = try OpenSkySaveCrimeDecoder.decodeStolenGoods(payload)
        case OpenSkySaveFormat.ChunkTag.violentCrimeGold:
            body.violentCrimeGold = try OpenSkySaveCrimeDecoder.decodeViolentGold(payload)
        case OpenSkySaveFormat.ChunkTag.harvests:
            body.harvests = try OpenSkySaveHarvestDecoder.decodeHarvests(payload)
        case OpenSkySaveFormat.ChunkTag.harvestDays:
            body.harvestDays = try OpenSkySaveHarvestDecoder.decodeHarvestDays(payload)
        case OpenSkySaveFormat.ChunkTag.locks:
            body.locks = try OpenSkySaveLockDecoder.decodeLocks(payload)
        default:
            try applyStory(tag: tag, payload: payload, to: &body)
        }
    }

    /// `CLOK` payload: one `Float64` bit pattern of the clock's total game
    /// seconds. A non-finite or negative value is corruption, not a clock.
    static func decodeClock(_ payload: Data) throws -> GameClock {
        guard payload.count == MemoryLayout<UInt64>.size else {
            throw OpenSkySaveError.invalidValue(
                context: "CLOK payload is \(payload.count) bytes, expected 8"
            )
        }
        var payloadReader = SaveReader(payload)
        let seconds = try Double(bitPattern: payloadReader.uint64("CLOK total game seconds"))
        guard seconds.isFinite, seconds >= 0 else {
            throw OpenSkySaveError.invalidValue(
                context: "CLOK total game seconds is \(seconds), expected a finite value >= 0"
            )
        }
        return GameClock(totalGameSeconds: seconds)
    }
}

nonisolated extension OpenSkySaveDecoder {
    /// Rejects a declared element count that cannot possibly fit in the bytes
    /// left, before anything reserves storage for it. Without this a corrupt
    /// four-byte count is an out-of-memory crash rather than a thrown error.
    public static func validate(
        count: UInt32,
        minimumElementSize: Int,
        remaining: Int,
        chunk: String
    ) throws {
        guard Int(count) <= remaining / minimumElementSize else {
            throw OpenSkySaveError.invalidCount(
                chunk: chunk,
                count: count,
                remaining: remaining
            )
        }
    }
}
