// A vanilla caster's spell list from the real install: the NPC_ `SPLO` run,
// through the template chain and its leveled lists, granted into a live
// `SpellbookState` as the combat loop does. `LvlBanditWizard` (`0x0001E79F`) is
// pinned: its own record has no spells, its seven come through a template, and
// its attack spells sit behind two `LVSP` lists. Editor IDs and counts only.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyMagic
@testable import OpenSkyMagicInterface
@testable import OpenSkyWorldState
import Testing

struct ActorSpellBaselineRealDataTests {
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
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    @MainActor
    func aPinnedVanillaCastersKnownSpellsAreItsRecordsOwnList() throws {
        let session = try Session(root: #require(RealDataEnvironment.dataRoot))
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
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    @MainActor
    func theCastersHostileSpellsArriveThroughItsLeveledSpellLists() throws {
        let session = try Session(root: #require(RealDataEnvironment.dataRoot))
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
        // Resolved through `RepositoryLogs` rather than the working directory,
        // which in a test host is `/` — the rule the other real-data suites
        // that leave artifacts behind follow.
        let directory = try RepositoryLogs.directory("actor-spell-baseline")
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
