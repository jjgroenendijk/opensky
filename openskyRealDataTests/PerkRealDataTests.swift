// Env-gated PERK sweep over the user's read-only active load order: decode
// every record, pin a few well-known perks, and report the entry-point
// histogram that scopes which entry points the perk runtime has to implement
// first (issue 20.4). Counts and editor IDs only — no game bytes leave the run.

import Foundation
@testable import opensky
import Testing

struct PerkRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    @Test(.enabled(if: Self.dataRoot != nil))
    func decodesEveryPerkRecordAndReportsTheEntryPointHistogram() throws {
        let root = try #require(Self.dataRoot)
        let plugins = ActivePluginFiles.load(root: root)
        let index = RecordIndex(plugins: plugins, recordTypes: ["MGEF", "SPEL", "SCRL", "PERK"])
        let definitions = index.definitions(of: "PERK")
        var decodedCount = 0
        var tally = PerkTally()
        var unknownEntryPoints: [UInt8: Int] = [:]
        var unknownFunctions: [UInt8: Int] = [:]

        for indexed in definitions {
            let perk = try Perk(record: indexed.record, localized: indexed.localized)
            decodedCount += 1
            tally.merge(perk.skipped)
            for effect in perk.effects {
                guard case let .entryPoint(payload) = effect.data else { continue }
                if !payload.entryPoint.isKnown {
                    unknownEntryPoints[payload.entryPoint.rawValue, default: 0] += 1
                }
                if case let .unknown(raw) = payload.function {
                    unknownFunctions[raw, default: 0] += 1
                }
            }
        }

        // Skyrim.esm carries 523 perks; the DLC masters add their own and
        // override some, which is where the rest of the 532 definitions and the
        // gap down to 483 winning identities come from.
        #expect(definitions.count >= 532)
        #expect(decodedCount == definitions.count)
        #expect(unknownEntryPoints.isEmpty)
        #expect(unknownFunctions.isEmpty)
        // Every field PERK authors is read, so nothing is silently dropped.
        #expect(tally.total == 0)

        let store = PerkStore(index: index)
        #expect(store.records.count >= 483)
        #expect(store.records.count <= definitions.count)
        try expectEffectMix(in: store)
        try expectPinnedPerks(in: store)
        report(store: store, definitions: definitions.count, tally: tally)
    }

    /// The three effect shapes, all of which vanilla authors, and the entry
    /// points they hook. Zero on any of them would mean a union branch stopped
    /// decoding without anything else noticing.
    private func expectEffectMix(in store: PerkStore) throws {
        let effects = store.perks.flatMap(\.effects)
        let counts = effects.reduce(into: [PerkEffectType: Int]()) {
            $0[$1.effect.type, default: 0] += 1
        }
        #expect(counts[.entryPoint, default: 0] >= 622)
        #expect(counts[.ability, default: 0] >= 32)
        #expect(counts[.quest, default: 0] >= 28)
        #expect(counts.keys.count == 3)

        // The most-hooked entry point by a wide margin, which is what the perk
        // runtime implements first.
        let histogram = store.entryPointHistogram
        #expect(histogram.count >= 68)
        let top = try #require(histogram.first)
        #expect(top.entryPoint == PerkEntryPoint(rawValue: 35)) // Mod Attack Damage
        #expect(top.count >= 81)
        let matches = store.matches(at: top.entryPoint)
        #expect(matches.count == top.count)
        // Every effect the index points at is reachable through the store.
        #expect(matches.allSatisfy { store.effect($0) != nil })
        // Ability effects resolve to real spells rather than dangling links.
        let abilities = effects.filter { $0.effect.type == .ability }
        #expect(abilities.allSatisfy { $0.spell != nil })
    }

    /// Vanilla perks pinned by editor ID, so a decode regression in the effect
    /// union shows up as a failed assertion rather than as a quietly emptier
    /// perk.
    private func expectPinnedPerks(in store: PerkStore) throws {
        let armsman = try #require(store.perk(editorID: "Armsman00"))
        #expect(armsman.record.isPlayable)
        #expect(store.rankChain(from: armsman.id).compactMap(\.editorID)
            == ["Armsman00", "Armsman20", "Armsman40", "Armsman60", "Armsman80"])
        let armsmanEffect = try #require(armsman.effects.first)
        #expect(armsmanEffect.entryPoint == PerkEntryPoint(rawValue: 35)) // Mod Attack Damage
        #expect(armsmanEffect.effect.conditionTabs.isEmpty == false)

        let augmented = try #require(store.perk(editorID: "AugmentedFlames"))
        #expect(store.rankChain(from: augmented.id).compactMap(\.editorID)
            == ["AugmentedFlames", "AugmentedFlames60"])
        // Mod Spell Magnitude, the entry point every magic-damage perk hooks.
        #expect(augmented.effects.first?.entryPoint == PerkEntryPoint(rawValue: 29))

        // The widest effect list in the set: one record hooking a dozen entry
        // points at once.
        let boosts = try #require(store.perk(editorID: "AlchemySkillBoosts"))
        #expect(boosts.effects.count >= 13)
        #expect(boosts.effects.allSatisfy { $0.entryPoint != nil })
    }

    /// The DATA byte at offset 2 is not the length of the record's `NNAM`
    /// chain: vanilla authors 1 on every rank of `Armsman`, whose chain is five
    /// records long, and xEdit computes the rank count it displays after load
    /// rather than reading it. Pinned so nothing starts trusting the byte.
    @Test(.enabled(if: Self.dataRoot != nil))
    func theDeclaredRankCountDoesNotTrackTheRankChain() throws {
        let root = try #require(Self.dataRoot)
        let index = RecordIndex(
            plugins: ActivePluginFiles.load(root: root),
            recordTypes: ["PERK"]
        )
        let store = PerkStore(index: index, spells: SpellStore(index: index))
        let armsman = try #require(store.perk(editorID: "Armsman00"))

        #expect(armsman.declaredRankCount == 1)
        #expect(store.rankChain(from: armsman.id).count == 5)

        // Every vanilla record leaves the level byte at zero and none is a
        // trait: the skill a perk requires lives in the record's conditions,
        // not in the header.
        let headers = store.perks.compactMap(\.record.data)
        #expect(headers.count == store.records.count)
        #expect(headers.allSatisfy { $0.level == 0 })
        #expect(headers.allSatisfy { !$0.isTrait })
        #expect(headers.contains { $0.isHidden })
        #expect(headers.contains { !$0.isPlayable })
        #expect(headers.contains { $0.rankCount == 5 })
    }

    private func report(store: PerkStore, definitions: Int, tally: PerkTally) {
        let histogram = store.entryPointHistogram
        let hooked = histogram.reduce(0) { $0 + $1.count }
        print(
            "[INFO] PERK definitions \(definitions), winning \(store.records.count), "
                + "effects \(store.perks.reduce(0) { $0 + $1.effects.count }), "
                + "entry-point effects \(hooked), "
                + "distinct entry points \(histogram.count), "
                + "unread fields \(tally.total)"
        )
        for entry in histogram {
            print("[INFO]   entry point \(entry.entryPoint): \(entry.count)")
        }
    }
}
