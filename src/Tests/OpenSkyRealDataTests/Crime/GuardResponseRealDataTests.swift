// Guard recognition on the real load order: the `GFAC` default object names
// the faction of every vanilla guard, so a Whiterun guard polices
// `CrimeFactionWhiterun`, and the crime faction's `STOL` and `JAIL` links
// resolve to the identities an arrest uses. Counts, editor IDs, and keys only.

import Foundation
@testable import OpenSkyCrimeInterface
@testable import OpenSkyFactionsInterface
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import Testing

struct GuardResponseRealDataTests {
    private static let crimeFactionEditorID = "CrimeFactionWhiterun"
    /// Observed on the local install as the `GFAC` target.
    private static let guardFactionEditorID = "IsGuardFaction"
    /// A vanilla guard whose `CRIF` and `SNAM` were checked by hand.
    private static let pinnedGuardEditorID = "GuardWhiterunImperialPatrolDay"

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func recognisesVanillaGuardsAndResolvesTheJailLinks() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let index = RecordIndex(
            plugins: ActivePluginFiles.load(root: root),
            recordTypes: RecordIndex.referenceRecordTypes
        )
        let store = FactionStore(index: index)
        let guardFaction = try #require(store.guardFaction)
        #expect(guardFaction.editorID == Self.guardFactionEditorID)

        let whiterun = try #require(store.faction(editorID: Self.crimeFactionEditorID))
        let whiterunKey = ReferenceKey(resolved: whiterun.id)
        let chest = store.linkKey(whiterun.faction.evidenceChest, of: whiterun)
        let marker = store.linkKey(whiterun.faction.exteriorJailMarker, of: whiterun)
        print(
            "[INFO] \(Self.crimeFactionEditorID) evidence chest "
                + "\(chest.map(\.description) ?? "-"), "
                + "jail marker \(marker.map(\.description) ?? "-")"
        )
        #expect(chest != nil)
        #expect(marker != nil)

        let policed = try policedFactions(root: root, store: store)
        let recognised = policed.values.count { $0 != nil }
        let policingWhiterun = policed.values.count { $0 == whiterunKey }
        print(
            "[INFO] NPC_ bases \(policed.count), recognised guards \(recognised), "
                + "policing \(Self.crimeFactionEditorID) \(policingWhiterun)"
        )
        let pinned = policed[Self.pinnedGuardEditorID].flatMap(\.self)
        #expect(pinned == whiterunKey)
        #expect(recognised > 100)
        #expect(policingWhiterun > 0)
    }

    /// Every `Skyrim.esm` NPC_ base with an editor ID, mapped to the crime
    /// faction it polices — nil when it is not a guard — resolved through the
    /// `useFactions` template chain the way an instantiated actor is.
    private func policedFactions(
        root: GameDataRoot,
        store: FactionStore
    ) throws -> [String: ReferenceKey?] {
        let esmURL = root.dataURL.appending(path: "Skyrim.esm")
        let file = try ESMFile(url: esmURL)
        let plugin = esmURL.lastPathComponent
        let localized = (try? file.pluginHeader().isLocalized) ?? false
        let resolver = ActorTemplateResolver.build(from: file, localized: localized)
        var policed: [String: ReferenceKey?] = [:]
        for base in resolver.actors.values {
            guard
                let editorID = base.editorID,
                let resolved = try? resolver.resolveFactions(base: base.formID)
            else { continue }
            let memberships = store.memberships(resolved.factions.value, fromPlugin: plugin)
                .compactMap { membership in
                    membership.faction.map {
                        ActorFactionMembership(
                            faction: ReferenceKey(resolved: $0.id),
                            rank: membership.rank
                        )
                    }
                }
            let crimeFaction = resolved.crimeFaction
                .flatMap { store.resolvedID($0, fromPlugin: plugin) }
                .map(ReferenceKey.init(resolved:))
            let profile = ActorSocialProfile(
                key: .player,
                memberships: ActorFactionState(memberships: memberships),
                crimeFaction: crimeFaction
            )
            policed[editorID] = GuardRecognition.policedFaction(
                of: profile,
                guardFaction: store.guardFactionKey
            )
        }
        return policed
    }
}
