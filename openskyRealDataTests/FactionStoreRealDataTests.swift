// Env-gated FACT decode, faction-store and NPC_ membership acceptance over the
// user's own read-only load order (issue #501).
//
// Four questions, in the order milestone M21 needs them answered: does every
// FACT record in the masters decode, do the pinned Whiterun crime and guard
// factions carry the values the spec describes, does every LCTN crime-faction
// link find its record, and does a vanilla Whiterun guard resolve a non-empty
// membership list through the `useFactions` template chain.
//
// Counts, editor IDs and tallies only — no game bytes leave the run
// (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky
import Testing

struct FactionStoreRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    /// The hold's crime faction, and the faction its guards belong to. Editor
    /// IDs rather than FormIDs, so a patch that moves a record does not fail
    /// the suite for the wrong reason.
    private static let crimeFactionEditorID = "CrimeFactionWhiterun"
    private static let guardFactionEditorID = "GuardFactionWhiterun"
    /// Every vanilla Whiterun guard's base record is named this way
    /// (`WhiterunGuardFixture`).
    private static let guardEditorIDPrefix = "GuardWhiterun"

    @Test(.enabled(if: Self.dataRoot != nil))
    func decodesEveryFactionAndResolvesTheCrimeAndGuardJoins() throws {
        let root = try #require(Self.dataRoot)
        let plugins = ActivePluginFiles.load(root: root)
        let index = RecordIndex(
            plugins: plugins,
            recordTypes: RecordIndex.referenceRecordTypes
        )
        let store = FactionStore(index: index)

        #expect(index.collectedCount(of: "FACT") >= 1414)
        #expect(store.factions.count == index.count(of: "FACT"))
        print(
            "[INFO] FACT collected \(index.collectedCount(of: "FACT")), "
                + "winning \(index.count(of: "FACT")), decoded \(store.factions.count), "
                + "crime \(store.crimeFactions.count), vendor \(store.vendorFactions.count)"
        )
        reportTallies(store)

        let crime = try #require(store.faction(editorID: Self.crimeFactionEditorID))
        let values = try #require(crime.faction.crimeValues)
        print(
            "[INFO] \(Self.crimeFactionEditorID) murder \(values.murder), "
                + "assault \(values.assault), trespass \(values.trespass), "
                + "pickpocket \(values.pickpocket), "
                + "steal multiplier \(values.stealMultiplier ?? -1), "
                + "escape \(values.escape ?? 0), werewolf \(values.werewolf ?? 0), "
                + "relations \(crime.faction.relations.count)"
        )
        #expect(crime.faction.tracksCrime)
        #expect(values.arrest)
        #expect(values.murder == 1000)
        #expect(crime.faction.exteriorJailMarker != nil)
        #expect(crime.faction.evidenceChest != nil)
        #expect(crime.faction.jailOutfit != nil)
        #expect(crime.faction.sharedCrimeFactionList != nil)

        let guards = try #require(store.faction(editorID: Self.guardFactionEditorID))
        #expect(guards.faction.editorID == Self.guardFactionEditorID)

        try checkLocationCrimeFactionLinks(index: index, store: store)
        try checkGuardMemberships(root: root, store: store, guardFaction: guards)
    }

    /// Every LCTN `FNAM` in the load order has to name a FACT the store holds:
    /// crime response (issues #504 and #505) reads exactly this link.
    private func checkLocationCrimeFactionLinks(
        index: RecordIndex,
        store: FactionStore
    ) throws {
        let locations = LocationStore(index: index)
        var linked: [String] = []
        var unresolved: [String] = []
        for resolved in locations.locations.values {
            guard let raw = resolved.location.crimeFaction else { continue }
            let name = resolved.location.editorID ?? resolved.id.description
            linked.append(name)
            if store.resolve(raw, fromPlugin: resolved.sourcePlugin) == nil {
                unresolved.append(name)
            }
        }
        print(
            "[INFO] LCTN crime-faction links \(linked.count) \(linked.sorted()), "
                + "unresolved \(unresolved.count) \(unresolved.sorted())"
        )
        // Only the hold locations carry one, and every one of the nine does
        // (docs/formats/factions.md "Observed counts").
        #expect(linked.count == 9)
        #expect(unresolved.isEmpty)
    }

    /// A vanilla Whiterun guard, resolved the way an instantiated actor will
    /// be: the SNAM run through `useFactions`, then joined against the store.
    private func checkGuardMemberships(
        root: GameDataRoot,
        store: FactionStore,
        guardFaction: ResolvedFaction
    ) throws {
        let esmURL = root.dataURL.appending(path: "Skyrim.esm")
        let file = try ESMFile(url: esmURL)
        let plugin = esmURL.lastPathComponent
        let localized = (try? file.pluginHeader().isLocalized) ?? false
        let resolver = ActorTemplateResolver.build(from: file, localized: localized)

        var guardBases: [ActorBase] = []
        var inheritedMemberships = 0
        var totalMemberships = 0
        var membersOfGuardFaction = 0
        for base in resolver.actors.values.sorted(by: { $0.formID.rawValue < $1.formID.rawValue }) {
            guard let resolved = try? resolver.resolveFactions(base: base.formID) else { continue }
            let memberships = store.memberships(
                resolved.factions.value,
                fromPlugin: plugin
            )
            totalMemberships += memberships.count
            if resolved.factions.source != base.formID {
                inheritedMemberships += 1
            }
            if memberships.contains(where: { $0.faction?.id == guardFaction.id }) {
                membersOfGuardFaction += 1
            }
            if base.editorID?.hasPrefix(Self.guardEditorIDPrefix) == true {
                guardBases.append(base)
            }
        }
        print(
            "[INFO] NPC_ bases \(resolver.actors.count), memberships \(totalMemberships), "
                + "inherited through useFactions \(inheritedMemberships), "
                + "members of \(Self.guardFactionEditorID) \(membersOfGuardFaction), "
                + "\(Self.guardEditorIDPrefix)* bases \(guardBases.count)"
        )
        #expect(!guardBases.isEmpty)
        #expect(membersOfGuardFaction > 0)
        #expect(inheritedMemberships > 0)

        for base in guardBases.prefix(3) {
            let resolved = try resolver.resolveFactions(base: base.formID)
            let memberships = store.memberships(resolved.factions.value, fromPlugin: plugin)
            let names = memberships.map { "\($0.displayName)#\($0.rank)" }
            print("[INFO] \(base.editorID ?? "-") memberships \(names)")
            let allResolved = memberships.allSatisfy(\.isResolved)
            #expect(!memberships.isEmpty)
            #expect(allResolved)
        }
    }

    /// What the decoder did not read, summed over every winning record. A
    /// nonzero unknown-field entry is the signal that the layout misses a
    /// subrecord the install actually carries.
    private func reportTallies(_ store: FactionStore) {
        var malformed: [FourCC: Int] = [:]
        var unknown: [FourCC: Int] = [:]
        var trailing: [FourCC: Int] = [:]
        var radiusHighWord = 0
        for resolved in store.factions.values {
            let skipped = resolved.faction.skipped
            malformed.merge(skipped.malformedFields, uniquingKeysWith: +)
            unknown.merge(skipped.unknownFields, uniquingKeysWith: +)
            trailing.merge(skipped.trailingBytes, uniquingKeysWith: +)
            radiusHighWord += skipped.vendorRadiusHighWordSet
        }
        print(
            "[INFO] FACT tallies malformed \(sortedText(malformed)), "
                + "unknown \(sortedText(unknown)), "
                + "trailing \(sortedText(trailing)), "
                + "VENV disputed radius high word set \(radiusHighWord)"
        )
        #expect(malformed.isEmpty)
    }

    /// A tally as text, ordered by field type so two runs print the same line.
    private func sortedText(_ counts: [FourCC: Int]) -> String {
        counts
            .map { "\($0.key) \($0.value)" }
            .sorted()
            .joined(separator: ", ")
    }
}
