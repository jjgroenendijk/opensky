// The alias fill pass: turns one quest's authored aliases into the table of world
// references its scripts, conditions, and journal text read. It is pure, so the
// fill rules are unit-testable without a store or an actor.
// The rules and the fill types not done yet are in docs/engine/quest-state.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuestsInterface

/// Fills one quest's reference aliases. The rules are in docs/engine/quest-state.md.
nonisolated public enum QuestAliasFiller: Sendable {
    /// Runs the pass over `quest.aliases` in file order.
    ///
    /// - Parameter resolver: master-list resolver of the plugin that defines
    ///   `quest`, which is what turns an ALFR FormID into a session-stable key.
    public static func fill(
        _ quest: Quest,
        resolver: FormIDResolver,
        locations: LocationStore? = nil
    ) -> QuestAliasFillResult {
        var pass = FillPass(resolver: resolver, locations: locations)
        for alias in quest.aliases {
            pass.fill(alias)
        }
        return pass.result
    }

    /// Accumulating state of one pass, so `fill(_:resolver:)` stays a
    /// statement per documented rule rather than one long function.
    private struct FillPass {
        let resolver: FormIDResolver
        let locations: LocationStore?
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
                fillLocation(alias)
                return
            }
            guard case .specificReference = alias.fillType else {
                skipped.note(.unsupportedFillType(alias.fillType))
                // An unimplemented fill type is OpenSky's gap, not the quest's,
                // so it never fails a start.
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
                // Refused, but never a start failure: the wiki does not say
                // which fill types the reuse rule covers.
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

        private mutating func fillLocation(_ alias: Quest.Alias) {
            guard case .specificLocation = alias.fillType, let locations else {
                skipped.note(.locationAlias)
                return
            }
            guard
                let raw = alias.forcedLocation,
                let resolved = locations.resolve(raw, fromPlugin: resolver.pluginName)
            else {
                skipped.note(.unresolvedLocation)
                note(unfilled: alias)
                return
            }
            state = state.fillingLocation(alias.id, with: resolved.id)
            if let forced = alias.forceIntoAlias, forced >= 0 {
                state = state.fillingLocation(UInt32(bitPattern: forced), with: resolved.id)
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
