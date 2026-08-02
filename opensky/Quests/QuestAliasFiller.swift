// The alias fill pass (issue #183, roadmap item 13.4): turning one quest's
// authored alias definitions into the table of world references its scripts,
// conditions and journal text read.
//
// A pure function of a `Quest` record plus a `FormIDResolver`, with no store
// and no actor, so the documented rules below are unit-testable on their own
// and the runtime layer only has to decide when to run it.
//
// Documented semantics, all from the Creation Kit wiki's alias reference
// (<https://ck.uesp.net/wiki/Alias>) rather than from memory:
//
// * Order. "The list of aliases is an ordered list - when the quest starts,
//   aliases are filled in order, and the order can matter in the case of
//   aliases which are directly or indirectly ... dependent on each other", and
//   "because the aliases are filled in order, dependencies can only be to
//   aliases higher in the list". So the fill order is the ALST/ALLS order the
//   record was written in, which is exactly `Quest.aliases`. There is no
//   priority between *fill types*; the priority is positional.
// * Optional. "Optional: If checked, the quest is not required to fill this in
//   order to start. If unchecked, the quest will fail to start if it cannot
//   fill this alias." That is why an unfilled non-optional alias is reported
//   back as a start failure rather than as an empty slot.
// * Reuse. "Normally, the game will not fill two aliases on the same quest
//   with the same reference. If 'Allow Reuse in Quest' is checked, the
//   reference in this alias CAN be placed into another alias on this quest
//   during the startup process." The flag is checked on the *second* alias:
//   "This option must be checked on any alias that can be filled with a
//   reference that has already been used, not on the first alias that uses the
//   reference."
// * Force into alias. "Force Into Alias When Filled: The specified alias will
//   also be filled with whatever fills this alias", and "the last 'source'
//   alias that is filled will be the one that determines the final value for
//   the specified 'target' alias. The quest does not stop performing the force
//   fill on the first match." Last writer wins, which falls out of running the
//   list in order.
//
// Stated deviations, so the gaps are facts rather than surprises:
//
// * Specific Reference (ALFR) is the only fill type implemented. Every other
//   type is a counted `QuestAliasSkipKind.unsupportedFillType` and leaves the
//   alias empty. It is deliberately *not* treated as a fill failure: refusing
//   to start a quest because OpenSky cannot run a Find Matching Reference
//   search would be this engine's limitation wearing the game's semantics.
//   Only a fill type OpenSky does implement, producing nothing, fails a
//   non-optional alias.
// * Location aliases are skipped wholesale — locations are not modelled — and
//   are an engine gap rather than a fill failure for the same reason, so a
//   non-optional one does not stop its quest from starting.
// * The reuse rule refuses the *fill* and never the *start*. The same page
//   says the rule "is not required for all fill types" and names Unique Actor
//   as one exception without listing the rest, so which fill types it really
//   covers is not documented. Treating a refusal as a start failure would
//   refuse thirteen quests `Skyrim.esm` ships that way — `DA01`, `MG05` and
//   `MQResurrectDragon` among them — on a reading the wiki does not support.
//   The refusal is counted, so the twenty aliases it affects stay visible.
// * "Reserves Reference" is decoded and not enforced. Reservation is a
//   cross-quest rule ("the game will not fill any other alias with this
//   reference"), so honouring it needs every running quest's table consulted
//   during every other quest's fill; with one implemented fill type the only
//   thing it could do today is refuse an authored, explicit reference.
// * A filled reference is not checked for existence, for being alive, enabled
//   or destroyed. `FormIDResolver` proves the FormID names a plugin OpenSky
//   loaded; proving the placement exists needs a whole-world REFR index, and
//   the Allow Dead / Allow Disabled / Allow Destroyed flags need actor state
//   that item 13.4 does not reach. All four are recorded here rather than
//   guessed at.
//
// Documented in docs/engine/runtime-state.md.

import Foundation

/// What one fill pass produced: the table, why each empty alias is empty, and
/// whether the quest is allowed to start with it.
nonisolated struct QuestAliasFillResult: Equatable, Sendable {
    /// The filled table, ready to be stored as a component.
    let state: QuestAliasState
    /// Reason-tagged count of every alias left empty.
    let skipped: QuestAliasTally
    /// Non-optional aliases that an implemented fill type failed to fill, in
    /// alias-list order. Non-empty means the quest must not start.
    let unfilledRequired: [UInt32]

    /// Whether the quest may start with this table, which is the documented
    /// meaning of the Optional checkbox.
    var canStartQuest: Bool {
        unfilledRequired.isEmpty
    }
}

/// Fills one quest's reference aliases. See the file header for the rules and
/// the deviations.
nonisolated enum QuestAliasFiller {
    /// Runs the pass over `quest.aliases` in file order.
    ///
    /// - Parameter resolver: master-list resolver of the plugin that defines
    ///   `quest`, which is what turns an ALFR FormID into a session-stable key.
    static func fill(_ quest: Quest, resolver: FormIDResolver) -> QuestAliasFillResult {
        var pass = FillPass(resolver: resolver)
        for alias in quest.aliases {
            pass.fill(alias)
        }
        return pass.result
    }

    /// Accumulating state of one pass, so `fill(_:resolver:)` stays a
    /// statement per documented rule rather than one long function.
    private struct FillPass {
        let resolver: FormIDResolver
        var state = QuestAliasState()
        var skipped = QuestAliasTally()
        var unfilledRequired: [UInt32] = []

        var result: QuestAliasFillResult {
            QuestAliasFillResult(
                state: state,
                skipped: skipped,
                unfilledRequired: unfilledRequired
            )
        }

        mutating func fill(_ alias: Quest.Alias) {
            guard alias.category == .reference else {
                // Locations are not modelled at all, so a location alias is an
                // engine gap like an unimplemented fill type and never fails a
                // start either.
                skipped.note(.locationAlias)
                return
            }
            guard case .specificReference = alias.fillType else {
                skipped.note(.unsupportedFillType(alias.fillType))
                // An unimplemented fill type is OpenSky's gap, not the quest's,
                // so it never fails a start (see the file header).
                return
            }
            guard
                let id = alias.forcedReference,
                let key = ReferenceKey.resolve(id, using: resolver)
            else {
                skipped.note(.unresolvedReference)
                note(unfilled: alias)
                return
            }
            guard alias.flags.contains(.allowReuseInQuest) || !state.holds(key) else {
                // Refused, but never a start failure — see the file header.
                skipped.note(.reusedInQuest)
                return
            }
            store(alias.id, key)
            if let forced = alias.forceIntoAlias, forced >= 0 {
                // Last writer wins by construction: a later alias forcing the
                // same target simply overwrites this.
                store(UInt32(bitPattern: forced), key)
            }
        }

        /// Records the fill, and the forced-into fill, under one rule so both
        /// land in the same normalized table.
        private mutating func store(_ aliasID: UInt32, _ key: ReferenceKey) {
            state = state.filling(aliasID, with: key)
        }

        /// A non-optional alias an implemented path could not fill is what
        /// stops the quest from starting.
        private mutating func note(unfilled alias: Quest.Alias) {
            guard !alias.flags.contains(.optional) else { return }
            unfilledRequired.append(alias.id)
        }
    }
}
