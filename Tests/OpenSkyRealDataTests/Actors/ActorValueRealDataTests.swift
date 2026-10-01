// Actor-value derivation checked on the real install. For every auto-calc NPC_,
// the derived health, magicka, and stamina must equal the values the Creation
// Kit baked into DNAM (<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/NPC_>).
// DNAM is only compared against, never used. Named-NPC numbers come from
// `openskycli actor-values --npc <editor-id>`.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import Testing

/// One pinned expectation, spelled as a type rather than a tuple so the
/// fixture list stays readable and the strict lint limits stay satisfied.
private struct NamedActor {
    let formID: UInt32
    let editorID: String
    let values: ActorValues
    let level: Int

    init(
        _ formID: UInt32,
        _ editorID: String,
        _ health: Float,
        _ magicka: Float,
        _ stamina: Float,
        level: Int
    ) {
        self.formID = formID
        self.editorID = editorID
        values = ActorValues(health: health, magicka: magicka, stamina: stamina)
        self.level = level
    }
}

struct ActorValueRealDataTests {
    private func resolver(root: GameDataRoot) throws -> ActorValueResolver {
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        return ActorValueResolver.build(
            from: file,
            localized: (try? file.pluginHeader().isLocalized) ?? false,
            pluginName: "Skyrim.esm",
            settings: ActorValueLevelSettings.resolve(
                store: GameSettingLoader.load(root: root, baseFile: file)
            )
        )
    }

    /// The two game settings the per-level spread reads, as `Skyrim.esm`
    /// actually authors them. Observed 2026-08-07 through
    /// `openskycli actor-values --race NordRace`, which prints both.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func theLevelSettingsMatchTheDocumentedDefaults() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let settings = ActorValueLevelSettings.resolve(
            store: GameSettingLoader.load(root: root, baseFile: file)
        )
        #expect(settings == .documentedDefaults)
    }

    /// Every playable race authors the same level-1 attributes, which is why
    /// `ActorValueBaselineResolver` can have one documented player fallback.
    /// Observed through `openskycli actor-values --race <editor-id>`.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func playableRacesShareTheirStartingAttributes() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let resolver = try resolver(root: root)
        let playable = resolver.races.values
            .filter { $0.flags.contains(.playable) && $0.stats.startingHealth > 0 }
        #expect(playable.count >= 10, "expected the vanilla playable races")
        for race in playable {
            let stats = race.stats
            let editorID = race.editorID ?? "\(race.formID)"
            #expect(stats.startingHealth == 50, "\(editorID) starting health")
            #expect(stats.startingMagicka == 50, "\(editorID) starting magicka")
            #expect(stats.startingStamina == 50, "\(editorID) starting stamina")
            // UESP "Skyrim:Health" reports 0.7% per second out of combat; the
            // record is where that number comes from.
            #expect(stats.healthRegenPercent == 0.7, "\(editorID) health regen")
            #expect(stats.magickaRegenPercent == 3, "\(editorID) magicka regen")
            #expect(stats.staminaRegenPercent == 5, "\(editorID) stamina regen")
        }
    }

    /// Named vanilla NPCs, with the numbers observed from probed data. The
    /// player's 100/100/100 is `NordRace`'s 50 plus the `Player` record's +50
    /// ACBS offsets, not a constant anyone typed.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func derivesNamedVanillaActors() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let resolver = try resolver(root: root)
        let expected = [
            NamedActor(0x0000_0007, "Player", 100, 100, 100, level: 1),
            NamedActor(0x0001_3BAC, "Heimskr", 75, 50, 70, level: 4),
            NamedActor(0x0001_3BBF, "Nazeem", 75, 60, 60, level: 4),
            NamedActor(0x0001_3BA1, "Belethor", 75, 60, 60, level: 4),
            NamedActor(0x0001_3475, "Alvor", 131, 68, 86, level: 10),
            NamedActor(0x0002_BF9F, "Hadvar", 171, 50, 64, level: 5),
            NamedActor(0x0001_414D, "Ulfric", 155, 50, 80, level: 10)
        ]
        for actor in expected {
            let base = FormID(actor.formID)
            #expect(
                resolver.templates.actors[actor.formID]?.editorID == actor.editorID,
                "\(base) is not \(actor.editorID) in this load order"
            )
            let resolved = try resolver.resolve(base: base)
            #expect(resolved.maximums == actor.values, "\(actor.editorID) derived values")
            #expect(resolved.level == actor.level, "\(actor.editorID) level")
        }
    }

    /// `EncBandit04TemplateMelee` (`0001E60D`): race health 50 plus its +125
    /// offset is 175, but DNAM says 170. The Creation Kit only refreshes DNAM
    /// when the Stats tab is reopened (<https://ck.uesp.net/wiki/Stats_Tab>).
    private static let staleTemplate = FormID(0x0001_E60D)

    /// Every auto-calc NPC_ with a baked DNAM derives to it, or inherits the one
    /// stale template. Actors whose template chain does not resolve are counted.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func derivationMatchesEveryBakedDNAMTriple() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let resolver = try resolver(root: root)
        var compared = 0
        var unresolved = 0
        var stale = 0
        var mismatches: [String] = []
        for raw in resolver.templates.actors.keys.sorted() {
            let resolved: ResolvedActorValues
            do {
                resolved = try resolver.resolve(base: FormID(raw))
            } catch {
                unresolved += 1
                continue
            }
            // Only an auto-calc record's DNAM is authoritative; UESP records
            // that the words are junk otherwise. A PC-level-mult actor is
            // skipped too: its baked values were computed against whatever
            // player level the editor last saw, and OpenSky has no player level
            // before M18 (`ActorValueResolver.playerLevel` is 1).
            guard
                resolved.autoCalculatesStats,
                !resolved.usesPlayerLevelMultiplier,
                let baked = resolved.bakedValues
            else {
                continue
            }
            compared += 1
            guard resolved.maximums != baked else { continue }
            guard resolved.statsSource != Self.staleTemplate else {
                stale += 1
                continue
            }
            let editorID = resolver.templates.actors[raw]?.editorID ?? "\(FormID(raw))"
            mismatches.append(
                "\(editorID) level \(resolved.level) stats from \(resolved.statsSource): "
                    + "derived \(resolved.maximums) vs DNAM \(baked)"
            )
        }
        #expect(compared > 1000, "expected a large auto-calc population, got \(compared)")
        let report = "\(mismatches.count)/\(compared) derivations disagree with DNAM; "
            + "first 10: \(mismatches.prefix(10).joined(separator: "; "))"
        #expect(mismatches.isEmpty, "\(report)")
        // Pinned rather than merely tolerated: if a future load order changes
        // how many records inherit the stale template, this says so.
        #expect(stale == 26, "expected 26 records inheriting the stale template, got \(stale)")
        #expect(
            unresolved < compared / 10,
            "\(unresolved) NPC_ records did not resolve their template chain"
        )
    }

    // MARK: - Non-primary actor values

    /// `iAVDSkillsLevelUp`, which UESP states as "the fixed 8 skill points per
    /// level" and `Skyrim.esm` authors at exactly that. Observed 2026-08-16
    /// through `openskycli gmst list --prefix iavd`.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func theSkillPointSettingMatchesTheDocumentedDefault() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let settings = ActorValueLevelSettings.resolve(
            store: GameSettingLoader.load(root: root, baseFile: file)
        )
        #expect(settings.skillPointsPerLevel == 8)
    }

    /// Nord race skill bonuses, as documented: "Two-Handed +10; One-Handed,
    /// Block, Light Armor, Smithing, Speech +5" (<https://en.uesp.net/wiki/Skyrim:Nord>).
    /// All six matching shows the DATA 0x00 decode is aligned.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func theNordSkillBonusesMatchTheDocumentedOnes() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let resolver = try resolver(root: root)
        let nord = try #require(resolver.races.values.first { $0.editorID == "NordRace" })
        let bonuses = Dictionary(
            uniqueKeysWithValues: nord.stats.skillBonuses.map { ($0.actorValue, $0.bonus) }
        )
        #expect(bonuses[7] == 10) // Two-Handed
        for skill in [6, 9, 10, 12, 17] { // One-Handed, Block, Smithing, Light Armor, Speech
            #expect(
                bonuses[Int32(skill)] == 5,
                "\(ActorValueIdentity.description(of: Int32(skill)))"
            )
        }
        #expect(nord.stats.skillBonuses.count == 6)
        // The other three RACE DATA fields that are actor values by name.
        #expect(nord.stats.baseCarryWeight == 300)
        #expect(nord.stats.baseMass == 1)
        #expect(nord.stats.unarmedDamage == 4)
    }

    /// Every playable race authors the same carry weight and mass, and a full
    /// set of skill bonuses — which is what lets the derived table be built
    /// from the race alone for a player who has not picked a class.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func everyPlayableRaceAuthorsTheSameNonPrimaryBaselines() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let resolver = try resolver(root: root)
        let playable = resolver.races.values
            .filter { $0.flags.contains(.playable) && $0.stats.startingHealth > 0 }
        #expect(playable.count >= 10, "expected the vanilla playable races")
        for race in playable {
            let editorID = race.editorID ?? "\(race.formID)"
            #expect(race.stats.baseCarryWeight == 300, "\(editorID) carry weight")
            #expect(race.stats.baseMass == 1, "\(editorID) mass")
            // Every playable race spends the same budget: one +10 and five +5.
            let total = race.stats.skillBonuses.reduce(0) { $0 + $1.bonus }
            #expect(total == 35, "\(editorID) skill bonus total")
        }
    }

    /// The whole derived table for one named vanilla actor, with the numbers
    /// observed through `openskycli actor-values --npc EncBandit03TemplateMelee`
    /// (2026-08-16) rather than recalled: a level-9 Nord bandit whose class
    /// weights One-Handed, Block, Light Armor and Heavy Armor.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func derivesTheNonPrimaryTableForANamedActor() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let resolver = try resolver(root: root)
        let resolved = try resolver.resolve(base: FormID(0x0001_BCDA))
        let values = resolved.generalBaseValues
        #expect(resolved.level == 9)
        // 15 floor + 5 Nord bonus + 17 from the class spread.
        #expect(values[6] == 37) // One-Handed
        #expect(values[7] == 42) // Two-Handed: floor + 10, no class weight
        #expect(values[8] == 15) // Archery: floor alone
        #expect(values[ActorValueIndex.speedMult] == 100)
        #expect(values[ActorValueIndex.carryWeight] == 300)
        #expect(values[ActorValueIndex.mass] == 1)
        #expect(values[ActorValueIndex.unarmedDamage] == 4)
        // Eighteen skills plus the four record-authored values, and nothing
        // else: no resistance is derived from records, so every one of them
        // reads the documented zero default.
        #expect(values.count == 22)
        #expect(values[ActorValueIndex.resistFire] == nil)
    }

    /// Every `GetActorValue` (14) and `GetActorValuePercent` (640) condition in
    /// `Skyrim.esm`, by whether OpenSky answers its actor value. The miss bucket
    /// must stay empty, so a new out-of-table index fails loudly.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func everyActorValueConditionInSkyrimESMResolvesItsParameter() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        var total = 0
        var primaries = 0
        var misses: [Int32: Int] = [:]
        ESMWalk.forEachRecord(in: file) { record in
            guard let fields = try? record.fields() else { return true }
            var list = ConditionList()
            for field in fields {
                _ = try? list.decode(field: field)
            }
            for condition in list.conditions where Self.actorValueFunctions.contains(
                condition.functionIndex
            ) {
                total += 1
                let index = condition.parameter1.asInt32
                if ActorValueIdentity.kind(at: index) != nil {
                    primaries += 1
                } else if !ActorValueIdentity.isVanilla(index: index) {
                    misses[index, default: 0] += 1
                }
            }
            return true
        }
        #expect(total > 100, "expected a real actor-value condition population, got \(total)")
        #expect(primaries < total, "expected non-primary actor-value conditions in the corpus")
        #expect(misses.isEmpty, "unreadable actor-value parameters: \(misses)")
    }

    /// `GetActorValue` and `GetActorValuePercent`, the two condition functions
    /// whose first parameter is `ptActorValue` (xEdit `wbDefinitionsTES5.pas`).
    private static let actorValueFunctions: Set<UInt16> = [14, 640]
}
