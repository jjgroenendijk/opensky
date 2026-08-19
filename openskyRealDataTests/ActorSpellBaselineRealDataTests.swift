// A vanilla caster's spell list, against the user's own install (issue #473,
// roadmap item 19.10, scope point 7): the NPC_ `SPLO` run resolved through the
// template chain and the leveled spell lists it routes through, granted into a
// live `SpellbookState` exactly as the combat loop grants it.
//
// Read-only against the install and headless: it builds the same engine types
// the app wires — `ActorSpellBaselineResolver` and `SpellbookRuntime` — with no
// window and no renderer.
//
// The actor is pinned rather than searched for, so a regression shows up as a
// failure rather than as the suite quietly picking a different actor.
// `LvlBanditWizard` (`0x0001E79F`) is the pin, and it is the interesting shape
// rather than the convenient one: its own record carries no spell list at all,
// its seven entries arrive through a template, four of them resolve to SPEL
// records that buff or heal, and its attack spells sit behind two `LVSP` lists.
//
// It writes a one-line summary into gitignored `logs/` so a pull request can
// link the run. Editor IDs and counts only: no game bytes leave the machine
// (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky
import Testing

struct ActorSpellBaselineRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    /// `LvlBanditWizard`, the pinned caster.
    private static let banditWizard = FormID(0x0001_E79F)

    @MainActor
    private struct Session {
        let plugin: String
        let baselines: ActorSpellBaselineResolver
        let spellbook: SpellbookRuntime

        init(root: GameDataRoot) throws {
            let esmURL = root.dataURL.appending(path: "Skyrim.esm")
            let file = try ESMFile(url: esmURL)
            plugin = esmURL.lastPathComponent
            let localized = (try? file.pluginHeader().isLocalized) ?? false
            baselines = ActorSpellBaselineResolver(
                actorValues: ActorValueResolver.build(
                    from: file,
                    localized: localized,
                    pluginName: plugin
                )
            )
            let index = RecordIndex(
                plugins: ActivePluginFiles.load(root: root, baseFile: file),
                recordTypes: ["MGEF", "SPEL", "SCRL", "EQUP"]
            )
            spellbook = SpellbookRuntime(
                store: WorldStateStore(),
                spells: SpellStore(index: index, effects: MagicEffectStore(index: index)),
                equipSlots: EquipSlotStore(index: index)
            )
        }

        /// The holder an instantiated actor of `base` would have.
        func holder(_ base: FormID) -> ActorValueHolder {
            ActorValueHolder(
                key: .plugin(name: plugin.lowercased(), objectID: base.rawValue),
                subject: .actor(base: base),
                cell: nil
            )
        }
    }

    /// The acceptance shape: instantiate a pinned vanilla caster and check that
    /// what it knows is exactly what its records say, with nothing invented and
    /// nothing dropped.
    @Test(.enabled(if: Self.dataRoot != nil))
    @MainActor
    func aPinnedVanillaCastersKnownSpellsAreItsRecordsOwnList() throws {
        let session = try Session(root: #require(Self.dataRoot))
        let baseline = session.baselines.baseline(for: Self.banditWizard)
        #expect(!baseline.actorSpells.isEmpty)

        let holder = session.holder(Self.banditWizard)
        let expected = session.spellbook.resolve(baseline.all, fromPlugin: session.plugin)
        #expect(!expected.isEmpty)

        let granted = session.spellbook.grant(expected, to: holder)

        #expect(granted == expected.count)
        #expect(session.spellbook.state(of: holder).known.sorted() == expected.sorted())
        for spell in expected {
            #expect(session.spellbook.knows(spell, holder))
        }
        // Granting twice adds nothing, which is what makes the combat loop's
        // per-actor grant safe to call on every step.
        #expect(session.spellbook.grant(expected, to: holder) == 0)

        try writeSummary(session: session, holder: holder, baseline: baseline)
    }

    /// The finding this item is built on: a vanilla caster's *attack* spells
    /// arrive through `LVSP` entries, so an engine that only resolved SPEL
    /// links would give it nothing it could throw at anybody.
    @Test(.enabled(if: Self.dataRoot != nil))
    @MainActor
    func theCastersHostileSpellsArriveThroughItsLeveledSpellLists() throws {
        let session = try Session(root: #require(Self.dataRoot))
        let baseline = session.baselines.baseline(for: Self.banditWizard)
        let spells = session.spellbook.resolve(baseline.all, fromPlugin: session.plugin)
            .compactMap { session.spellbook.record($0) }

        let hostile = spells.filter { spell in
            spell.spellType == .spell
                && spell.effects.contains {
                    $0.effect?.effect.data?.flags.contains(.hostile) == true
                }
        }

        #expect(!hostile.isEmpty)
        // Every one of them is a delivery this build carries out, which is what
        // makes them options the combat machine can actually choose.
        for spell in hostile {
            let delivery = spell.data?.delivery ?? .selfTarget
            #expect(delivery != .selfTarget)
            #expect(
                SpellDelivery.isImplemented(delivery, castingType: spell.data?.castingType)
            )
            #expect(spell.cost.cost > 0)
        }
    }

    /// One line into a run directory under gitignored `logs/`, so a pull
    /// request can link the run rather than describe it.
    @MainActor
    private func writeSummary(
        session: Session,
        holder: ActorValueHolder,
        baseline: ActorSpellBaseline
    ) throws {
        let known = session.spellbook.knownSpells(of: holder)
            .map { $0.editorID ?? $0.key.description }
            .sorted()
        // Anchored on the source file rather than the working directory, which
        // in a test host is `/` — the rule the other real-data suites that
        // leave artifacts behind follow.
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "logs")
            .appending(path: "actor-spell-baseline")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let text = """
        19.10 actor spell baseline, issue #473
        actor:          LvlBanditWizard (0001E79F)
        SPLO entries:   \(baseline.actorSpells.count)
        race entries:   \(baseline.raceSpells.count)
        known spells:   \(known.count)
        \(known.map { "  \($0)" }.joined(separator: "\n"))

        """
        try text.write(
            to: directory.appending(path: "summary.txt"),
            atomically: true,
            encoding: .utf8
        )
    }
}
