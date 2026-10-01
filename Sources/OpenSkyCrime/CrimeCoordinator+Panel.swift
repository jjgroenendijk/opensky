// The `World > Crime & Factions` panel's reading half. Every value comes from
// the runtime the session itself consults, so the panel cannot disagree with
// the world.

import OpenSkyCrimeInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldInterface
import OpenSkyWorldState

extension CrimeCoordinator {
    public var crimeFactionSnapshot: CrimeFactionControlSnapshot {
        guard let reporter, let world, world.hasFactionData else { return .unavailable }
        let store = reporter.runtime.factions
        let options = factionOptions(store)
        let subject = subjectReadout(panel.subject ?? .player, store: store)
        let override = panel.vendorOverride
        return CrimeFactionControlSnapshot(
            isAvailable: true,
            bounties: CrimeCore.bountyReadouts(reporter.runtime.ledger(), factions: store),
            currentCrimeFaction: crimeFaction(in: world.currentCellLocation)
                .map { CrimeCore.factionOption($0, in: store) },
            ownership: world.targetOwnership(),
            ownerName: CrimeCore.ownerName(targetOwner(), in: store),
            stolenStacks: world.stolenPlayerStacks(),
            crimeFactions: options.crime,
            selectedCrimeFaction: panel.bountyFaction ?? options.crime.first?.key,
            playerMemberships: membershipReadouts(of: .player, store: store),
            subject: subject,
            factions: options.all,
            selectedFaction: panel.membershipFaction ?? options.all.first?.key,
            vendorFactions: options.vendors,
            vendorOverride: override,
            effectiveVendor: override.flatMap { world.vendor(faction: $0) } ?? subject.vendor,
            hour: world.hourOfDay,
            lastCrimeText: lastActionText,
            lastGuardText: lastGuardText,
            lastActionText: panel.lastActionText
        )
    }

    /// The selection, or the first crime faction, matching the popup.
    var effectiveBountyFaction: ReferenceKey? {
        guard let store = reporter?.runtime.factions else { return nil }
        return panel.bountyFaction ?? factionOptions(store).crime.first?.key
    }

    /// The selection, or the first faction, matching the popup.
    var effectiveMembershipFaction: ReferenceKey? {
        guard let store = reporter?.runtime.factions else { return nil }
        return panel.membershipFaction ?? factionOptions(store).all.first?.key
    }

    // MARK: - Private

    private func factionOptions(_ store: FactionStore) -> CrimeFactionOptions {
        if let cached = panel.options {
            return cached
        }
        let built = CrimeCore.factionOptions(store)
        panel.options = built
        return built
    }

    /// The owner the crosshair verdict was reached against, which may be the
    /// cell's rather than the reference's own.
    private func targetOwner() -> ReferenceOwner? {
        guard
            let interaction = world?.crosshairInteraction,
            let entry = world?.references?.referenceEntry(formID: interaction.reference)
        else { return nil }
        return ownershipVerdict(on: entry.key).owner
    }

    private func membershipReadouts(
        of key: ReferenceKey,
        store: FactionStore
    ) -> [MembershipReadout] {
        (world?.factionMemberships(of: key)?.memberships ?? []).map {
            MembershipReadout(
                faction: CrimeCore.factionOption($0.faction, in: store), rank: $0.rank
            )
        }
    }

    private func subjectReadout(_ key: ReferenceKey, store: FactionStore) -> SocialSubjectReadout {
        let profile = world?.socialProfile(of: key)
        let policed = profile.flatMap {
            GuardRecognition.policedFaction(of: $0, guardFaction: store.guardFactionKey)
        }
        return SocialSubjectReadout(
            key: key,
            name: key == .player ? "the player" : world?.actorName(key) ?? key.description,
            memberships: membershipReadouts(of: key, store: store),
            towardPlayer: key == .player ? nil : profile.flatMap { world?.reactionTerms(of: $0) },
            crimeFaction: profile?.crimeFaction.map { CrimeCore.factionOption($0, in: store) },
            policedFaction: policed.map { CrimeCore.factionOption($0, in: store) },
            vendor: world?.vendor(of: key)
        )
    }
}
