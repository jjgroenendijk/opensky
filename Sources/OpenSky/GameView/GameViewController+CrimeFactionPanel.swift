// The `World > Crime & Factions` panel's reading half (issue #507, roadmap item
// 21.8): one snapshot of the bounty ledger, the crosshair's ownership verdict,
// the player's stolen goods, both actors' memberships, the derivation terms
// between them and the subject's guard and vendor roles.
//
// Every value comes from the runtime the session itself consults — the ledger
// `GetCrimeGold` reads, the verdict a take is judged by, the derivation the
// combat loop asks — so the panel cannot disagree with the world it describes.
// The actions live in `GameViewController+CrimeFactionActions.swift`.

import AppKit
import OpenSkyEngine
import OpenSkyFormatsESM
import OpenSkyGameData

/// What the panel has selected. Nil selections fall back to the first option
/// the snapshot offers, which is what the popups show.
struct CrimeFactionPanelState {
    var bountyFaction: ReferenceKey?
    var membershipFaction: ReferenceKey?
    var vendorOverride: ReferenceKey?
    /// The actor the membership and vendor controls act on; nil is the player.
    var subject: ReferenceKey?
    var lastActionText = "No crime or faction action yet."
    /// The popups' faction lists, built once per load order: a vanilla load
    /// order carries well over a thousand factions, and sorting them twice a
    /// second for a list that cannot change would be waste.
    var options: CrimeFactionOptions?
}

/// The three faction lists the panel's popups offer, sorted by name.
struct CrimeFactionOptions {
    let all: [FactionOption]
    let crime: [FactionOption]
    let vendors: [FactionOption]
}

extension GameViewController {
    var crimeFactionSnapshot: CrimeFactionControlSnapshot {
        guard let reporter = crime.reporter, factions.runtime != nil else {
            return .unavailable
        }
        let store = reporter.runtime.factions
        let options = crimeFactionOptions(store)
        let subject = socialSubjectReadout(crime.panel.subject ?? .player, store: store)
        let override = crime.panel.vendorOverride
        let here = crimeFaction(in: streamer?.currentCellLocation)
        return CrimeFactionControlSnapshot(
            isAvailable: true,
            bounties: bountyReadouts(reporter.runtime),
            currentCrimeFaction: here.map { factionOption($0, store) },
            ownership: targetOwnership(),
            ownerName: targetOwnerName(store),
            stolenStacks: worldItems.runtime.map {
                readout($0.inventory.inventory(of: $0.player).stacks.filter(\.stolen))
            } ?? [],
            crimeFactions: options.crime,
            selectedCrimeFaction: crime.panel.bountyFaction ?? options.crime.first?.key,
            playerMemberships: membershipReadouts(of: .player, store: store),
            subject: subject,
            factions: options.all,
            selectedFaction: crime.panel.membershipFaction ?? options.all.first?.key,
            vendorFactions: options.vendors,
            vendorOverride: override,
            effectiveVendor: override.flatMap(vendor(faction:)) ?? subject.vendor,
            hour: renderer?.gameClock.hourOfDay,
            lastCrimeText: crime.lastActionText,
            lastGuardText: crime.lastGuardText,
            lastActionText: crime.panel.lastActionText
        )
    }

    /// The faction the bounty controls write to: the selection, or the first
    /// crime faction when nothing is selected, matching the popup.
    var effectiveBountyFaction: ReferenceKey? {
        guard let store = crime.reporter?.runtime.factions else { return nil }
        return crime.panel.bountyFaction ?? crimeFactionOptions(store).crime.first?.key
    }

    /// The faction the membership controls act on, defaulted the same way.
    var effectiveMembershipFaction: ReferenceKey? {
        guard let store = crime.reporter?.runtime.factions else { return nil }
        return crime.panel.membershipFaction ?? crimeFactionOptions(store).all.first?.key
    }

    func factionOption(_ key: ReferenceKey, _ store: FactionStore) -> FactionOption {
        FactionOption(key: key, name: store.faction(key: key)?.displayName ?? key.description)
    }

    // MARK: - Private

    private func crimeFactionOptions(_ store: FactionStore) -> CrimeFactionOptions {
        if let cached = crime.panel.options {
            return cached
        }
        let sorted = store.sortedFactions
        func options(_ factions: [ResolvedFaction]) -> [FactionOption] {
            factions
                .map { FactionOption(key: ReferenceKey(resolved: $0.id), name: $0.displayName) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        let built = CrimeFactionOptions(
            all: options(sorted),
            crime: options(sorted.filter(\.faction.tracksCrime)),
            vendors: options(sorted.filter(\.faction.isVendor))
        )
        crime.panel.options = built
        return built
    }

    private func bountyReadouts(_ runtime: CrimeRuntime) -> [BountyReadout] {
        runtime.ledger().entries.filter { !$0.isEmpty }.map { entry in
            BountyReadout(
                faction: factionOption(entry.faction, runtime.factions),
                nonViolentGold: entry.nonViolentGold,
                violentGold: entry.violentGold,
                counts: entry.counts,
                response: CrimeResponsePolicy.response(
                    bounty: entry.gold,
                    values: runtime.factions.faction(key: entry.faction)?.faction.crimeValues
                )
            )
        }
    }

    /// Whose the reference under the crosshair is, by name: the owner the
    /// verdict was reached against, which may be the cell's rather than the
    /// reference's own.
    private func targetOwnerName(_ store: FactionStore) -> String? {
        guard
            let interaction = currentInteraction,
            let entry = streamer?.referenceEntry(formID: interaction.reference)
        else { return nil }
        switch ownershipVerdict(on: entry.key).owner {
        case nil:
            return nil
        case let .actor(base):
            return "NPC_ \(base)"
        case let .faction(key, requiredRank):
            return "\(factionOption(key, store).name) (rank \(requiredRank) or higher)"
        }
    }

    private func membershipReadouts(
        of key: ReferenceKey,
        store: FactionStore
    ) -> [MembershipReadout] {
        guard let runtime = seededFactionRuntime(for: key) else { return [] }
        return runtime.state(of: key).memberships.map {
            MembershipReadout(faction: factionOption($0.faction, store), rank: $0.rank)
        }
    }

    private func socialSubjectReadout(
        _ key: ReferenceKey,
        store: FactionStore
    ) -> SocialSubjectReadout {
        let profile = socialProfile(of: key)
        let policed = profile.flatMap {
            GuardRecognition.policedFaction(of: $0, guardFaction: store.guardFactionKey)
        }
        return SocialSubjectReadout(
            key: key,
            name: key == .player ? "the player" : dialogueSpeakerLabel(for: key),
            memberships: membershipReadouts(of: key, store: store),
            towardPlayer: key == .player ? nil : profile.flatMap(reactionTerms(of:)),
            crimeFaction: profile?.crimeFaction.map { factionOption($0, store) },
            policedFaction: policed.map { factionOption($0, store) },
            vendor: vendor(of: key)
        )
    }

    /// Every precedence term for what `observer` makes of the player, from the
    /// same derivation the combat loop asks.
    private func reactionTerms(of observer: ActorSocialProfile) -> ReactionTermsReadout? {
        guard
            let player = socialProfile(of: .player),
            let derivation = factions.runtime?.derivation
        else { return nil }
        return ReactionTermsReadout(
            decision: derivation.decide(observer, toward: player),
            hostilityOverride: observer.hostilityOverride,
            crime: derivation.crime.crimeReaction(of: observer, toward: player),
            relationship: derivation.relationshipReaction(of: observer, toward: player),
            scriptedRank: derivation.scriptedRank(of: observer, toward: player),
            faction: derivation.factionReaction(of: observer, toward: player)
        )
    }
}
