// Env-gated actor-value derivation sweep over the user's own Skyrim SE install
// (read-only external input, never committed — AGENTS.md Legal & IP).
//
// The strong check is the census: for every auto-calc NPC_ in Skyrim.esm, the
// derivation is compared against the three values the Creation Kit itself baked
// into that record's DNAM. DNAM is documented as the editor's own calculated
// health/magicka/stamina "if auto-calc stats is on"
// (<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/NPC_>), so it is an
// independent statement of the answer rather than a restatement of the formula.
// Nothing here feeds DNAM into the derivation; it is only ever compared to.
//
// The named-NPC test pins numbers observed from that same probed data — the
// output of `openskycli actor-values --npc <editor-id>` — never from memory.
//
// Skips automatically when OPENSKY_DATA_ROOT is unset or unresolvable (CI has
// no game data). Run with `make realtest`.

import Foundation
@testable import opensky
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
    /// Real data only when explicitly pointed at via the env var; the
    /// locator's Steam-default fallback is deliberately not consulted so
    /// machines without the override skip deterministically.
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    private func resolver(root: GameDataRoot) throws -> ActorValueResolver {
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        return ActorValueResolver.build(
            from: file,
            localized: (try? file.pluginHeader().isLocalized) ?? false,
            settings: ActorValueLevelSettings.resolve(
                store: GameSettingLoader.load(root: root, baseFile: file)
            )
        )
    }

    /// The two game settings the per-level spread reads, as `Skyrim.esm`
    /// actually authors them. Observed 2026-08-07 through
    /// `openskycli actor-values --race NordRace`, which prints both.
    @Test(.enabled(if: Self.dataRoot != nil))
    func theLevelSettingsMatchTheDocumentedDefaults() throws {
        let root = try #require(Self.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let settings = ActorValueLevelSettings.resolve(
            store: GameSettingLoader.load(root: root, baseFile: file)
        )
        #expect(settings == .documentedDefaults)
    }

    /// Every playable race authors the same level-1 attributes, which is why
    /// `ActorValueBaselineResolver` can have one documented player fallback.
    /// Observed through `openskycli actor-values --race <editor-id>`.
    @Test(.enabled(if: Self.dataRoot != nil))
    func playableRacesShareTheirStartingAttributes() throws {
        let root = try #require(Self.dataRoot)
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
    @Test(.enabled(if: Self.dataRoot != nil))
    func derivesNamedVanillaActors() throws {
        let root = try #require(Self.dataRoot)
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

    /// The one vanilla template whose baked DNAM contradicts its own ACBS.
    ///
    /// `EncBandit04TemplateMelee` (`0001E60D`) resolves its stats from itself:
    /// `NordRace`'s 50 starting health plus its own +125 health offset is 175,
    /// and its DNAM says 170. Its sibling `EncBandit03TemplateMelee` matches the
    /// same formula exactly, so the formula is not what differs — the baked
    /// value is stale. The Creation Kit documents that it can be: "one must
    /// refresh the Stats Tab (click on another tab then back to the Stats Tab)
    /// to update Calculated Health, Magicka, and Stamina if Attribute Offsets
    /// or underlying Race or Class Base Attributes change."
    /// (<https://ck.uesp.net/wiki/Stats_Tab>) Every record that inherits its
    /// stats inherits the stale number with them.
    private static let staleTemplate = FormID(0x0001_E60D)

    /// The census: every auto-calc NPC_ that carries a baked DNAM triple must
    /// derive to exactly that triple, or trace its stats to the one vanilla
    /// template whose baked value is stale.
    ///
    /// Actors whose template chain will not walk are counted and reported
    /// rather than failing the sweep — a dangling TPLT is the plugin's problem,
    /// and the derivation has nothing to say about one.
    @Test(.enabled(if: Self.dataRoot != nil))
    func derivationMatchesEveryBakedDNAMTriple() throws {
        let root = try #require(Self.dataRoot)
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
}
