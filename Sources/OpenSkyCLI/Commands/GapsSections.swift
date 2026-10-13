// The `gaps` sections. Each one runs a census from the module that owns the rule
// and turns it into done and left rows.

import Foundation
import OpenSkyBehavior
import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagic
import OpenSkyMenus
import OpenSkyProgression
import OpenSkyScripting
import OpenSkyWorld

extension GapsGatherer {
    func papyrus() throws -> GapSection {
        let loader = PexScriptLoader(fileSystem: fileSystem)
        let paths = loader.scriptPaths()
        let files = paths.compactMap { try? loader.load($0) }
        let census = PexNativeCensus(files: files)
        let registry = PapyrusNativeRegistry.standard
        return GapSection(
            title: "Papyrus natives",
            unit: "natives",
            done: census.coverage(in: registry).implemented,
            left: census.missing(in: registry),
            usesUnit: "call sites",
            notes: [
                "\(files.count) of \(paths.count) archived scripts parsed, "
                    + "\(census.referenceTotal) native call sites"
            ]
        )
    }

    func conditions() throws -> GapSection {
        var census = ConditionFunctionCensus()
        for plugin in try requirePlugins().plugins {
            ESMWalk.forEachRecord(in: plugin.file) { record in
                if let fields = try? record.fields() {
                    census.record(fields: fields)
                }
                return true
            }
        }
        let registry = ConditionFunctionRegistry.standard
        return GapSection(
            title: "Condition functions",
            unit: "functions",
            done: census.counts.keys.filter { registry[$0] != nil }.count,
            left: census.missing(in: registry).map {
                let number = Int($0.index) + ConditionFunctionRegistry.creationKitOffset
                let name = ConditionFunctionNames.name(for: $0.index) ?? "unnamed"
                return (name: "\(name) (\(number))", count: $0.count)
            },
            usesUnit: "conditions",
            notes: ["\(census.total) conditions in \(plugins.plugins.count) plugins"]
        )
    }

    func records() throws -> GapSection {
        var sweep = RecordCoverageSweep()
        for plugin in try requirePlugins().plugins {
            sweep.sweep(plugin.file)
        }
        var left: [(name: String, count: Int)] = []
        for (type, count) in sweep.counts {
            if sweep.missing[type] != nil {
                left.append(("\(type) has no decoder", count))
            } else if let failed = sweep.failureCounts[type] {
                left.append(("\(type) decode throws", failed))
            } else if let unread = sweep.unread[type], !unread.isEmpty {
                let detail = unread.sorted { $0.value > $1.value }.prefix(4)
                    .map { "\($0.key) \($0.value)" }.joined(separator: ", ")
                left.append(("\(type) leaves fields unread: \(detail)", unread.values.reduce(0, +)))
            }
        }
        return GapSection(
            title: "Record types",
            unit: "record types",
            done: sweep.counts.count - left.count,
            left: Self.ranked(left),
            usesUnit: "records",
            notes: ["\(sweep.recordTotal) records in \(plugins.plugins.count) plugins"]
                + sweep.failures.prefix(10).map { "first failures: \($0)" }
        )
    }

    func magic() throws -> GapSection {
        var skipped = SkippedRecords()
        let effects = try requirePlugins().decodeRecords(of: "MGEF", skipped: &skipped) {
            try MagicEffect(record: $0, localized: $1)
        }
        let census = MagicEffectGapCensus(effects: effects)
        return GapSection(
            title: "Magic effect archetypes",
            unit: "archetypes",
            done: census.appliedArchetypeCount,
            left: census.rankedUnapplied,
            usesUnit: "magic effects",
            notes: [
                "\(census.unappliedTotal) of \(census.effectTotal) magic effects apply nothing; "
                    + "\(census.undecoded) have no DATA, \(skipped.total) did not decode"
            ]
        )
    }

    func perks() throws -> [GapSection] {
        var skipped = SkippedRecords()
        let perks = try requirePlugins().decodeRecords(of: "PERK", skipped: &skipped) {
            try Perk(record: $0, localized: $1)
        }
        let census = PerkGapCensus(perks: perks)
        let unread = census.unreadEntryPoints
        let unsupported = census.unsupportedFunctions
        let note = "\(census.effectTotal) entry-point effects in \(perks.count) perks"
        return [
            GapSection(
                title: "Perk entry points",
                unit: "entry points",
                done: census.entryPoints.count - unread.count,
                left: unread,
                usesUnit: "perk effects",
                notes: [note]
            ),
            GapSection(
                title: "Perk entry-point functions",
                unit: "functions",
                done: census.functions.count - unsupported.count,
                left: unsupported,
                usesUnit: "perk effects",
                notes: [note]
            )
        ]
    }

    func behavior() -> [GapSection] {
        let sweep = BehaviorGapSweep.run(fileSystem: fileSystem)
        let tally = sweep.tally
        let missing = sweep.foldersWithoutSkeleton
        let note = "\(sweep.graphCount) graphs, \(sweep.eventsFired) events fired, "
            + "\(sweep.failures.count) files failed, "
            + "no skeleton: \(missing.isEmpty ? "none" : missing.joined(separator: ", "))"
        let bindings = tally.rankedUnappliedBindings.map { entry in
            (name: "binding not applied: \(entry.name)", count: entry.count)
        }
        let clips = tally.rankedUnresolvedClips.map { entry in
            (name: "clip not found: \(entry.name)", count: entry.count)
        }
        let features = tally.rankedFeatureGaps + bindings + clips
        return [
            GapSection(
                title: "Behavior node classes",
                unit: "node classes",
                done: sweep.doneClasses.count,
                left: sweep.leftClasses,
                usesUnit: "graph nodes",
                notes: [note, "done means reached by the sweep with no gap noted"]
            ),
            GapSection(
                title: "Behavior classes not reached",
                unit: "node classes",
                done: nil,
                left: sweep.unreachedClasses,
                usesUnit: "graph nodes",
                notes: ["no update reached these, so whether they work is unknown"]
            ),
            GapSection(
                title: "Behavior features ignored",
                unit: "features",
                done: nil,
                left: Self.ranked(features),
                usesUnit: "hits"
            )
        ]
    }

    func swf() -> [GapSection] {
        let sweep = MenuGapSweep.run(loader: SWFMovieLoader(fileSystem: fileSystem))
        let note = "\(sweep.movieCount) movies, \(sweep.loadFailures.count) failed to load, "
            + "\(MenuGapSweep.ticks) ticks each with no bridge"
        return [
            GapSection(
                title: "Menus with no bridge",
                unit: "engine-facing movies",
                done: sweep.bridgedMovieCount,
                left: sweep.unbridgedMovies,
                usesUnit: "GameDelegate names",
                notes: [note]
            ),
            GapSection(
                title: "AS2 runtime",
                unit: "names, opcodes, and faults",
                done: nil,
                left: sweep.runtimeGaps,
                usesUnit: "hits",
                notes: [
                    note,
                    "a name a movie reads before it sets it also counts, so not every row is a gap"
                ]
            )
        ]
    }

    static func ranked(_ rows: [(name: String, count: Int)]) -> [(name: String, count: Int)] {
        rows.sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }
}
