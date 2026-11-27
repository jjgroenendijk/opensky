// The alias fill pass: turns one quest's authored aliases into the table of world
// references its scripts, conditions, and journal text read. It is pure, so the
// fill rules are unit-testable without a store or an actor.
// The rules and the fill types not done yet are in docs/engine/quest-state.md.
// The Find Matching Reference search is in `QuestReferenceSearch.swift`.

import Foundation
public import OpenSkyConditions
public import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyQuestsInterface
import OpenSkyWorldState

/// Fills one quest's reference aliases. The rules are in docs/engine/quest-state.md.
nonisolated public enum QuestAliasFiller: Sendable {
    /// Runs the pass over `quest.aliases` in file order.
    /// - Parameter resolver: resolver of the plugin that defines `quest`, for ALFR keys.
    /// - Parameter event: the story event that starts the quest, for the event fill.
    /// - Parameter scope: the loaded world for the match-condition fills. Nil skips them.
    /// - Parameter running: the running quests' alias tables, for the external alias fill.
    public static func fill(
        _ quest: Quest,
        resolver: FormIDResolver,
        locations: LocationStore? = nil,
        event: StoryEventData? = nil,
        scope: QuestAliasSearchScope? = nil,
        translation: FormIDTranslation? = nil,
        running: [ReferenceKey: QuestAliasState] = [:]
    ) -> QuestAliasFillResult {
        var pass = FillPass(
            resolver: resolver, locations: locations, event: event, scope: scope,
            quest: quest.formID, translation: translation, running: running
        )
        for alias in quest.aliases {
            pass.fill(alias)
        }
        return pass.result
    }

    /// Accumulating state of one pass, so `fill(_:resolver:)` stays a
    /// statement per documented rule rather than one long function.
    fileprivate struct FillPass {
        let resolver: FormIDResolver
        let locations: LocationStore?
        let event: StoryEventData?
        let scope: QuestAliasSearchScope?
        let quest: FormID
        let translation: FormIDTranslation?
        let running: [ReferenceKey: QuestAliasState]
        var state = QuestAliasState()
        var creations: [QuestAliasCreation] = []
        var skipped = QuestAliasTally()
        var unfilledRequired: [UInt32] = []

        var result: QuestAliasFillResult {
            QuestAliasFillResult(
                state: state,
                skipped: skipped,
                unfilledRequired: unfilledRequired,
                creations: creations
            )
        }

        mutating func fill(_ alias: Quest.Alias) {
            guard alias.category == .reference else {
                fillLocation(alias)
                return
            }
            guard !fillByRule(alias) else { return }
            let key: ReferenceKey?
            switch alias.fillType {
            case .specificReference:
                key = alias.forcedReference
                    .flatMap { ReferenceKey.resolve($0, using: resolver)?.namingPlayer }
            case .uniqueActor where locations != nil:
                // A base with no single persistent actor is OpenSky's gap, so it
                // never fails a start.
                guard let unique = uniqueReference(of: alias) else {
                    skipped.note(.unresolvedReference)
                    return
                }
                key = unique
            case .locationAliasReference where locations != nil:
                guard let found = locationAliasKey(alias) else { return }
                key = found
            case .externalAlias:
                key = externalTable(of: alias).flatMap { table in
                    alias.externalAlias
                        .flatMap { table.reference(forAlias: UInt32(bitPattern: $0)) }
                }
            default:
                skipped.note(.unsupportedFillType(alias.fillType))
                // An unimplemented fill type is OpenSky's gap, not the quest's,
                // so it never fails a start.
                return
            }
            guard let key else {
                skipped.note(.unresolvedReference)
                note(unfilled: alias)
                return
            }
            guard allows(key, in: alias) else {
                skipped.note(.noMatch)
                note(unfilled: alias)
                return
            }
            guard alias.flags.contains(.allowReuseInQuest) || !state.holds(key) else {
                // Refused, but never a start failure: the wiki does not say
                // which fill types the reuse rule covers.
                skipped.note(.reusedInQuest)
                return
            }
            storeFilled(alias, key)
        }

        /// The fill types with their own rule. False when `alias` is none of them.
        private mutating func fillByRule(_ alias: Quest.Alias) -> Bool {
            switch alias.fillType {
            case .fromEvent:
                fillFromEvent(alias)
            case .createReferenceToObject:
                noteCreation(alias)
            default:
                guard let scope, alias.isMatchSearch else { return false }
                fillMatching(alias, scope: scope)
            }
            return true
        }

        /// `ALCA` low 16 bits name the alias to create at; bit 0x8000 means "create in" its
        /// inventory, which OpenSky does not do. The world makes the reference after the pass.
        private mutating func noteCreation(_ alias: Quest.Alias) {
            guard
                let base = alias.createdObject, let at = alias.createAt, at & 0x8000 == 0,
                let anchor = state.reference(forAlias: at & 0xFFFF)
            else {
                skipped.note(.unsupportedFillType(alias.fillType))
                return
            }
            let translated = translation?(base) ?? base
            creations.append(QuestAliasCreation(
                aliasID: alias.id,
                base: translated,
                anchor: anchor
            ))
        }

        /// Notes why nothing was found. An empty location alias may be OpenSky's gap,
        /// so only a searched location that lists no free reference fails the alias.
        private mutating func locationAliasKey(_ alias: Quest.Alias) -> ReferenceKey? {
            guard let place = locationOfAlias(alias) else {
                skipped.note(.unresolvedReference)
                return nil
            }
            guard let found = locationReference(of: alias, in: place) else {
                skipped.note(.noMatch)
                note(unfilled: alias)
                return nil
            }
            return found
        }

        /// `ALUA` names an NPC base; its one placed reference fills the alias. A base
        /// with no persistent actor takes its one loaded actor.
        private func uniqueReference(of alias: Quest.Alias) -> ReferenceKey? {
            guard
                let base = alias.uniqueActor
                    .flatMap({ ReferenceKey.resolve($0, using: resolver) })
            else { return nil }
            return locations?.uniqueActorReferences[base]
                ?? scope?.search.loadedActor(ofBase: base)
        }

        /// ALFA names a location alias and ALRT a location ref type. The first reference
        /// that location lists under the type, and that no other alias holds, fills it.
        private func locationOfAlias(_ alias: Quest.Alias) -> ResolvedFormID? {
            guard let raw = alias.aliasReference, raw >= 0 else { return nil }
            return state.location(forAlias: UInt32(raw))
        }

        /// The location and its child locations, in that order.
        private func locationReference(
            of alias: Quest.Alias, in place: ResolvedFormID
        ) -> ReferenceKey? {
            guard
                let locations,
                let type = alias.referenceType
                    .flatMap({ ReferenceKey.resolve($0, using: resolver) })
            else { return nil }
            return locations.specialReferencesWithChildren(ofType: type, in: place).first {
                alias.flags.contains(.allowReuseInQuest) || !state.holds($0)
            }
        }

        /// ALFE names the event, ALFD the member that fills the alias
        /// (<https://ck.uesp.net/wiki/Quest_Alias_Tab>).
        private mutating func fillFromEvent(_ alias: Quest.Alias) {
            let member = alias.eventData.flatMap {
                StoryEventData.Member(rawValue: UInt16(truncatingIfNeeded: $0))
            }
            // Without an event the fill is not possible, which is OpenSky's start
            // path, not the quest's fault, so it never fails the start.
            guard let event, let member else {
                skipped.note(.unsupportedFillType(alias.fillType))
                return
            }
            if alias.category == .reference, let key = event.reference(member) {
                let match = scope?.match(alias, quest: quest, filled: state)
                if let match, !match.conditionsPass(on: key) {
                    skipped.note(.noMatch)
                    note(unfilled: alias)
                    return
                }
                store(alias.id, key)
            } else if alias.category != .reference, let location = event.location(member) {
                state = state.fillingLocation(alias.id, with: location)
            } else {
                skipped.note(.unresolvedReference)
                note(unfilled: alias)
            }
        }

        private mutating func fillLocation(_ alias: Quest.Alias) {
            if case .fromEvent = alias.fillType {
                fillFromEvent(alias)
                return
            }
            if case .externalAlias = alias.fillType {
                fillExternalLocation(alias)
                return
            }
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

        /// Find Matching Reference: the loaded candidates, or the near alias's linked
        /// children, that pass the match conditions. Without "In Loaded Area", a loaded
        /// miss searches the persistent references outside it
        /// (docs/engine/quest-state.md). A miss fails a required alias only when every
        /// step that applies has run.
        private mutating func fillMatching(_ alias: Quest.Alias, scope: QuestAliasSearchScope) {
            guard let candidates = matchCandidates(alias, in: scope.search) else {
                skipped.note(.unresolvedReference)
                return
            }
            var found = chooseMatch(alias, from: candidates, scope: scope)
            var searchedEverywhere = alias.flags.contains(.matchInLoadedArea)
            if found == nil, !searchedEverywhere, let outside = scope.search.outsideLoadedArea() {
                searchedEverywhere = true
                let loaded = scope.search.references
                var outsideScope = scope
                outsideScope.search = outside
                let unloaded = matchCandidates(alias, in: outside)?.filter { loaded[$0] == nil }
                found = chooseMatch(alias, from: unloaded ?? [], scope: outsideScope)
            }
            guard let found else {
                skipped.note(.noMatch)
                if searchedEverywhere {
                    note(unfilled: alias)
                }
                return
            }
            store(alias.id, found)
            if let forced = alias.forceIntoAlias, forced >= 0 {
                store(UInt32(bitPattern: forced), found)
            }
        }

        /// The near alias's linked children, or every reference of `search`. Nil when the
        /// near alias is empty or names a near type other than 0, "Linked Ref Child".
        private func matchCandidates(
            _ alias: Quest.Alias, in search: QuestReferenceSearch
        ) -> [ReferenceKey]? {
            guard case .nearAlias = alias.fillType else { return search.references.sortedKeys() }
            guard
                let near = alias.nearAlias, near >= 0, (alias.nearType ?? 0) == 0,
                let parent = state.reference(forAlias: UInt32(near))
            else { return nil }
            return search.linkedChildren(of: parent)
        }

        private func chooseMatch(
            _ alias: Quest.Alias, from candidates: [ReferenceKey], scope: QuestAliasSearchScope
        ) -> ReferenceKey? {
            let match = scope.match(alias, quest: quest, filled: state)
            let held = state
            return match.choose(from: match.matches(candidates) { held.holds($0) })
        }
    }
}

nonisolated extension QuestAliasFiller.FillPass {
    /// The flag rules of a specific reference and a unique actor. A specific
    /// reference ignores "Allow Dead" and "Allow Disabled", and fails when deleted.
    fileprivate func allows(_ key: ReferenceKey, in alias: Quest.Alias) -> Bool {
        // An external alias fails only in the cases the Quest Alias Tab page names.
        guard let scope, alias.fillType != .externalAlias else { return true }
        let flags = alias.flags
        if !flags.contains(.allowReserved), scope.reserved.contains(key) {
            return false
        }
        if case .specificReference = alias.fillType {
            return !scope.search.deletes(key)
        }
        let state = scope.search.state(of: key)
        if state.isDead, !flags.contains(.allowDead) {
            return false
        }
        if state.isDisabled, !flags.contains(.allowDisabled) {
            return false
        }
        return flags.contains(.allowDestroyed) || !scope.search.destroys(key)
    }

    /// External Alias: `ALEQ` names the other quest and `ALEA` its alias. The alias takes
    /// what that alias holds now, and fails when the quest is not running or the alias
    /// is empty (<https://ck.uesp.net/wiki/Quest_Alias_Tab>).
    fileprivate func externalTable(of alias: Quest.Alias) -> QuestAliasState? {
        guard
            let raw = alias.externalQuest,
            let other = ReferenceKey.resolve(raw, using: resolver)
        else { return nil }
        return running[other]
    }

    fileprivate mutating func fillExternalLocation(_ alias: Quest.Alias) {
        guard
            let id = alias.externalAlias,
            let location = externalTable(of: alias)?.location(forAlias: UInt32(bitPattern: id))
        else {
            skipped.note(.unresolvedLocation)
            note(unfilled: alias)
            return
        }
        state = state.fillingLocation(alias.id, with: location)
    }
}

nonisolated extension QuestAliasFiller.FillPass {
    /// Records the fill, and the forced-into fill, under one rule so both
    /// land in the same normalized table.
    /// Stores the fill, and again in the alias it forces into. Last writer wins: a later
    /// alias forcing the same target overwrites this.
    fileprivate mutating func storeFilled(_ alias: Quest.Alias, _ key: ReferenceKey) {
        store(alias.id, key)
        if let forced = alias.forceIntoAlias, forced >= 0 {
            store(UInt32(bitPattern: forced), key)
        }
    }

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

nonisolated extension Quest.Alias {
    /// Find Matching Reference: a near-alias fill, or no fill subrecord but match
    /// conditions. An alias with neither is filled by script.
    var isMatchSearch: Bool {
        switch fillType {
        case .nearAlias: true
        case .none: !matchConditions.conditions.isEmpty
        default: false
        }
    }
}
