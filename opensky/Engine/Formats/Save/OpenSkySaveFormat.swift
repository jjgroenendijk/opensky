// OpenSky native save container (issue #161, roadmap item 10.1.4): the on-disk
// shape of a saved session.
//
// This is OpenSky's own format, not Bethesda's `.ess`. Nothing here is reverse
// engineered, so the layout is chosen for the properties this engine needs:
//
// - Deterministic bytes. Everything after the header metadata is a pure
//   function of the `WorldStateSnapshot` plus the load-order fingerprint, so
//   two sessions that reached the same end state through different mutation
//   orders write byte-identical files. Nothing in the encoder reads the clock
//   or a hash seed; the creation timestamp is injected by the caller and lives
//   in the header, outside the deterministic region.
// - Forward and backward tolerance. The body is a stream of tagged chunks, so
//   an older build skips a chunk a newer build added instead of refusing the
//   file. Component kinds inside a chunk are the opposite: they are versioned
//   by `formatVersion`, because a delta whose components were partly dropped
//   is a silently wrong world, not a degraded one.
// - Defensive decoding. Every count is checked against the bytes actually
//   remaining before an array is sized, so a corrupt length cannot make the
//   decoder allocate gigabytes (AGENTS.md: malformed input must not crash).
//
// Documented in docs/formats/opensky-save.md.

import Foundation

/// Names and version constants of the OpenSky native save container.
nonisolated enum OpenSkySaveFormat {
    /// File magic: ASCII "OSAV", four bytes, first in the file.
    static let magic = Data("OSAV".utf8)
    /// Version of the layout this build writes and is the only one it reads.
    static let currentVersion: UInt32 = 1
    /// File extension for saves written by this engine.
    static let fileExtension = "osav"

    /// Four-character chunk tags defined in version 1.
    enum ChunkTag {
        /// Generated-reference allocator position. Payload is exactly one
        /// `UInt64`.
        static let allocator = "GALC"
        /// Runtime reference deltas, one entry per dirty reference.
        static let referenceDeltas = "RDLT"
        /// Runtime global-variable overrides, one entry per overridden global
        /// (issue #165). Added after version 1 shipped and deliberately did not
        /// bump `currentVersion`: it is a new chunk, so an older build skips it
        /// by its declared length and loads the rest of the save, which is the
        /// tolerance the chunk stream exists to provide.
        static let globalValues = "GVAR"
        /// Game clock state (issue #164). Payload is exactly one `Float64`
        /// bit pattern: `GameClock.totalGameSeconds`. Additive like `GVAR` —
        /// an older build skips it, and a file without it restores the
        /// vanilla-start clock.
        static let clock = "CLOK"
        /// Papyrus script instance state (issue #171): one entry per live
        /// script instance, with its variables. Additive like `GVAR` and
        /// `CLOK` and deliberately does not bump `currentVersion` — an older
        /// build skips it by its declared length and loads the rest of the
        /// save, and a file without it restores a world whose scripts start
        /// from their compiled defaults. Script state is a new chunk rather
        /// than a new component kind inside `RDLT` for exactly this reason: a
        /// component kind is versioned by `formatVersion`, so putting it there
        /// would force every older build to refuse the file.
        static let papyrusScripts = "PSCR"
        /// Pending Papyrus update timers (issue #277): one entry per armed
        /// timer slot of a persistent script instance. Additive for the same
        /// reasons `PSCR` is and likewise does not bump `currentVersion` — an
        /// older build skips it by its declared length, and a file without it
        /// restores a world where no script has a pending `OnUpdate`. An empty
        /// timer list writes no chunk at all, so a session that armed no timer
        /// produces the bytes it produced before this chunk existed.
        static let papyrusTimers = "PTMR"
        /// Runtime inventories (issue #176): one entry per owner whose items
        /// deviate from plugin data, with its stacks and its equipped set.
        ///
        /// Inventory is a `WorldStateComponentKind` in the store but is *not*
        /// written inside `RDLT`, and that split is the whole point. A
        /// component kind inside `RDLT` is versioned by `formatVersion`, so
        /// putting inventory there would force every older build to refuse
        /// every save that has one. As its own chunk it is additive like
        /// `GVAR`, `CLOK`, `PSCR` and `PTMR`: an older build skips it by its
        /// declared length and loads the rest of the world. `RDLT` therefore
        /// omits the inventory component entirely, and omits an entry whose
        /// only component was inventory, so an older build sees exactly the
        /// bytes it would have written itself. The decoder merges the two back
        /// into one delta per reference. An owner with no runtime inventory
        /// writes nothing, and a session that touched none writes no chunk.
        static let inventories = "INVN"
        /// Spawned references (issue #177): one entry per object the running
        /// game placed in the world, such as a dropped item.
        ///
        /// Additive for the same reason `INVN` is, and split out for the same
        /// reason: a component kind inside `RDLT` is versioned by
        /// `formatVersion`, so an older build would refuse every save that
        /// contained one instead of loading the rest of the world without the
        /// dropped items. A session that spawned nothing writes no chunk.
        static let spawnedReferences = "SPWN"
        /// Quest runtime state (issue #182): one entry per quest whose running,
        /// stage or objective state deviates from plugin data.
        ///
        /// Additive for the same reason `INVN` and `SPWN` are, and split out of
        /// `RDLT` for the same reason: a component kind inside `RDLT` is
        /// versioned by `formatVersion`, so an older build would refuse every
        /// save containing quest state instead of loading the rest of the
        /// world. A session that touched no quest writes no chunk, so its bytes
        /// match what this encoder produced before the chunk existed.
        static let questStates = "QSTS"
        /// Filled quest aliases (issue #183): one entry per quest whose alias
        /// table is non-empty, and inside it one fill per filled alias.
        ///
        /// A sibling of `QSTS` rather than an extension of it, decided here
        /// because the two answer to different rules. `QSTS` entries are a flat
        /// positional layout with no per-entry length, so appending a field to
        /// them would make every older build misparse the *whole* chunk rather
        /// than skip the new part — the exact failure the chunk stream exists
        /// to avoid. As its own chunk the fills are additive like `INVN` and
        /// `SPWN`: an older build skips them by the declared length and
        /// restores a world whose quests run with empty aliases, and a session
        /// that filled none writes no chunk at all.
        static let questAliases = "QALS"
        /// Filled location aliases. Separate from QALS so old readers skip
        /// location targets instead of misparsing QALS's flat entries.
        static let questLocationAliases = "QLOC"
        /// Actor values (issue #194): one entry per actor whose current
        /// health, magicka or stamina deviates from a full baseline.
        ///
        /// Additive and split out of `RDLT` for the same reason `INVN`, `SPWN`,
        /// `QSTS` and `QALS` are: a component kind inside `RDLT` is versioned
        /// by `formatVersion`, so an older build would refuse every save
        /// containing a wounded actor instead of loading the rest of the world
        /// with everyone at full health. A session in which nothing took damage
        /// writes no chunk at all.
        ///
        /// Current values only. The maximums are a pure function of the RACE,
        /// CLAS and NPC_ records, so writing them would let a save carry a
        /// number a changed load order no longer authors.
        static let actorValues = "AVAL"

        /// Actor-value overrides (issue #496, roadmap item 20.3): one entry
        /// per actor holding one or more of the 164 actor values away from the
        /// baseline its records author, and inside it one record per value:
        /// index, base offset, permanent modifier, damage modifier.
        ///
        /// A sibling of `AVAL` rather than an extension of it, for the reason
        /// `QALS` is a sibling of `QSTS`: `AVAL` entries are a flat positional
        /// layout with no per-entry length, so appending a variable-length list
        /// to them would make every older build misparse the *whole* chunk
        /// instead of skipping the new part. As its own chunk it is additive
        /// like every chunk above — an older build skips it by the declared
        /// length and restores a world whose actors carry their record
        /// baselines, and a session that moved no value writes no chunk at all.
        ///
        /// It replaces item 19.5's `AVGN`, which carried an absolute base
        /// rather than an offset for the 161 non-primary values. A new tag
        /// rather than a reinterpreted payload, because the two layouts have
        /// identical shapes and different meanings: silently reading one as the
        /// other would turn a resistance of 30 into a resistance of 30 *above*
        /// what the records say. An `AVGN` chunk written by an older build is
        /// now an unknown tag and is skipped, so such a save restores actors at
        /// their record baselines — the same degradation an older build takes
        /// from this one.
        ///
        /// The temporary modifier is deliberately not written. It is an active
        /// magic effect's contribution, and the effect that established it is
        /// what re-establishes it on load (issue 19.6); persisting it as well
        /// would double the buff every time the save was reloaded.
        static let actorValueOverrides = "AVOV"

        /// Death states (issue #197, roadmap item 15.6): one entry per actor
        /// recorded dead, with the resting root transform its ragdoll settled
        /// at.
        ///
        /// Additive and split out of `RDLT` for the same reason `AVAL` is. A
        /// session in which nothing died writes no chunk at all, so its bytes
        /// match what this encoder produced before the chunk existed.
        ///
        /// The root transform only. Persisting the whole per-bone pose is the
        /// choice item 15.6 declined and documented, so a reloaded corpse lies
        /// where it fell in the skeleton's rest pose rather than in the tangle
        /// it died in (see docs/engine/ragdoll.md).
        static let deaths = "DETH"

        /// Hostility (issue #374, roadmap item 15.7): one entry per actor whose
        /// regard for the player deviates from neutral.
        ///
        /// Additive and split out of `RDLT` for the same reason `AVAL` and
        /// `DETH` are. A session in which nothing was provoked writes no chunk
        /// at all, so its bytes match what this encoder produced before the
        /// chunk existed.
        ///
        /// Hostility only. Whether the *player* is in combat is derived from
        /// which resident actors are hostile and alive, so writing it would let
        /// a save carry a fact that contradicts the world it was loaded into.
        static let combatStates = "CBTS"

        /// Dialogue said-state (issue #426, roadmap item 17.2): one entry per
        /// INFO a speaker has actually said.
        ///
        /// Additive and split out of `RDLT` for the same reason `QSTS` and
        /// `CBTS` are. A session in which nobody spoke writes no chunk at all,
        /// so its bytes match what this encoder produced before the chunk
        /// existed.
        ///
        /// Said-state only. Which topics a speaker offers is a pure function of
        /// the plugin records, the quest state `QSTS` already carries and this
        /// chunk, so writing the offered list would let a save carry a menu a
        /// changed load order no longer authors.
        static let dialogueStates = "DLGS"

        /// Active magic effects (issue #469, roadmap item 19.6): one entry per
        /// actor carrying a timed effect, each listing the effects with their
        /// remaining duration.
        ///
        /// Additive and split out of `RDLT` for the same reason `AVAL` and
        /// `DETH` are. A session in which nothing was applied writes no chunk at
        /// all, so its bytes match what this encoder produced before the chunk
        /// existed.
        ///
        /// This chunk is what makes `AVOV`'s dropped temporary modifier
        /// recoverable: each effect carries how much of each actor value's
        /// temporary slot it owns, and the load path re-establishes the slot
        /// from here rather than trusting a second copy on disk.
        ///
        /// Instant effects are not here and cannot be: a zero-duration effect
        /// moved an actor value once and the moved value is what `AVAL` and
        /// `AVOV` already carry.
        static let activeEffects = "AEFF"

        /// Spellbooks (issue #470, roadmap item 19.7): one entry per actor that
        /// knows a spell, has read a book, or has spent a greater power.
        ///
        /// Additive and split out of `RDLT` for the same reason `AEFF` is. A
        /// session in which nobody learned anything writes no chunk at all, so
        /// its bytes match what this encoder produced before the chunk existed.
        ///
        /// Readied hands travel here and casts do not. A readied spell is a
        /// loadout the player chose and has to survive a reload; a charge in
        /// progress is frame state, and restoring one would put the player back
        /// mid-cast with magicka already committed.
        static let spellbooks = "SPLB"

        /// Enchanted items (issue #472, roadmap item 19.9): one entry per owner
        /// whose enchanted weapons have spent charge or whose worn items
        /// established constant effects.
        ///
        /// Additive and split out of `RDLT` for the same reason `AEFF` and
        /// `SPLB` are. A session in which nothing enchanted fired and nothing
        /// enchanted was worn writes no chunk at all, so its bytes match what
        /// this encoder produced before the chunk existed.
        ///
        /// Charge travels here rather than inside `INVN` because a stack is not
        /// where charge belongs: `INVN` entries are counts, and a charge is a
        /// per-item float that changes on a hit rather than on a transfer. The
        /// worn-effect sequences beside it are the other half of the same fact —
        /// which of the `AEFF` effects each worn item is responsible for — and
        /// splitting the two would let a reload restore effects nothing could
        /// take back off.
        static let enchantedItems = "ECHG"

        /// Owned perks (issue #497, roadmap item 20.4): one entry per actor
        /// that owns at least one perk.
        ///
        /// Additive and split out of `RDLT` for the same reason `SPLB` is. A
        /// session in which nobody took a perk and no seeded NPC carries one
        /// writes no chunk at all, so its bytes match what this encoder
        /// produced before the chunk existed.
        ///
        /// Only the owned identities travel. A rank is the length of an owned
        /// `NNAM` chain rather than a stored number (`PerkState`), and the
        /// constant abilities perks grant are re-established from the owned set
        /// on load exactly as a worn enchantment's are — which is why nothing
        /// here duplicates what `AEFF` already carries.
        static let perks = "PRKS"

        /// Faction memberships (issue #503, roadmap item 21.3): one entry per
        /// actor that belongs to at least one faction.
        ///
        /// Additive and split out of `RDLT` for the same reason `PRKS` is: a
        /// session in which nothing asked who anybody sides with writes no
        /// chunk at all, so its bytes match what this encoder produced before
        /// the chunk existed.
        ///
        /// Memberships travel and hostility does not, even though the two are
        /// read together: hostility is derived from these memberships plus the
        /// records (`ActorReaction`), and the `CBTS` byte beside them is the
        /// explicit override alone. Writing a derived answer into the save
        /// would freeze a decision the next load should be making again — a
        /// plugin that changes a faction relation has to change who is angry.
        static let factions = "FCTN"

        /// The player's character-level progress (issue #499, roadmap item
        /// 20.6): one entry, and only when the player has left level 1 behind.
        ///
        /// Additive and split out of `RDLT` for the reason `PRKS` is: a session
        /// that never levelled writes no chunk at all, so its bytes match what
        /// this encoder produced before the chunk existed.
        ///
        /// The level, the banked experience, the perk-point pool, the owed
        /// picks and the picks already made travel. What a pick *did* does not:
        /// the ten points it added are a base override and ride in `AVOV`,
        /// which is where every session-made deviation from a derived baseline
        /// already lives.
        static let playerProgress = "PLVL"

        /// Crime ledgers (issue #504, roadmap item 21.5): one entry per actor
        /// that owes a crime faction gold or has offended one, and inside it
        /// one row per faction with the bounty and the four crime counts.
        ///
        /// Additive and split out of `RDLT` for the reason `FCTN` is: a
        /// law-abiding session writes no chunk at all, so its bytes match what
        /// this encoder produced before the chunk existed.
        ///
        /// Counts travel beside the gold because they are not derivable from
        /// it. An unwitnessed crime moves the count and not the bounty
        /// (<https://en.uesp.net/wiki/Skyrim:Crime>), so a save that carried
        /// only the gold would restore a world that had forgotten what the
        /// player did.
        static let crimeLedgers = "CRIM"

        /// Stolen goods (issue #504): for every owner holding stolen items,
        /// one row per item saying how many of its copies are stolen.
        ///
        /// A sibling of `INVN` rather than an extension of it, for the reason
        /// `QALS` is a sibling of `QSTS`: `INVN` entries are a flat positional
        /// layout with no per-entry length, so appending a flag to each stack
        /// would make every older build misparse the *whole* chunk instead of
        /// skipping the new part. `INVN` therefore keeps writing one row per
        /// item with honest and stolen copies summed — an older build restores
        /// a complete inventory that has simply forgotten which copies were
        /// stolen — and this chunk carries the split. A session in which
        /// nothing was stolen writes no chunk at all.
        static let stolenGoods = "STOL"
    }

    /// Discriminator byte in front of a serialized `ReferenceKey`.
    enum KeyTag {
        static let plugin: UInt8 = 0
        static let generated: UInt8 = 1
    }

    /// Discriminator byte in front of a serialized `CellSceneLocation`.
    enum CellTag {
        static let absent: UInt8 = 0
        static let exterior: UInt8 = 1
        static let interior: UInt8 = 2
    }

    /// Discriminator byte in front of a serialized `PapyrusValue` in `PSCR`.
    ///
    /// Only the five persistable kinds have a tag. `PapyrusValue.object` and
    /// `.array` hold runtime-allocated identity with no world meaning, so the
    /// encoder writes them as `none` rather than inventing a wire shape for a
    /// handle that means nothing after a reload.
    enum ValueTag {
        static let none: UInt8 = 0
        static let boolean: UInt8 = 1
        static let integer: UInt8 = 2
        static let float: UInt8 = 3
        static let string: UInt8 = 4
    }

    /// Bits of a `QSTS` entry's quest-level flag byte. Ours, not Bethesda's:
    /// the DNAM bits a QUST record carries describe what the plugin authored,
    /// while these two describe what the session did.
    enum QuestFlag {
        static let running: UInt8 = 1 << 0
        static let completed: UInt8 = 1 << 1
    }

    /// Bits of a `QSTS` objective's flag byte, in the order the three Papyrus
    /// natives are usually called: displayed, completed, failed.
    enum QuestObjectiveFlag {
        static let displayed: UInt8 = 1 << 0
        static let completed: UInt8 = 1 << 1
        static let failed: UInt8 = 1 << 2
    }
}
