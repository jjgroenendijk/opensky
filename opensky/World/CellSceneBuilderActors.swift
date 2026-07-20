// Actor streaming integration (milestone 5.5): ACHR placed actors build and
// evict with their owning cell on the serial build queue, like statics.
// Worldspace-persistent ACHRs are stored under the (0,0) persistent CELL and
// mapped into streamed cells by physical position — same ownership rule as
// persistent teleport doors (CellSceneBuilderInteriors.swift). Accounting is
// exact per cell: discovered = rendered + intentional skips + failures.
//
// References: UESP "Skyrim Mod:Mod File Format" ACHR/NPC_ pages; resolution
// chain + record layouts documented in docs/formats/actors.md.

import Foundation
import OSLog
import simd

/// Per-build actor accounting; folded into CellLoadSummary. The exact
/// invariant `discovered == rendered + disabledSkips + failures` is the 5.5
/// acceptance rule — every discovered ACHR must land in exactly one bucket.
nonisolated struct ActorBuildCounts {
    /// Non-deleted ACHRs owned by this cell: local persistent + temporary
    /// children plus position-mapped worldspace-persistent placements.
    var discovered = 0
    var rendered = 0
    /// Initially-disabled ACHRs (record-header flag 0x800): explicit
    /// intentional skip while M5 carries no quest/script state.
    var disabledSkips = 0
    /// Malformed ACHR records, unresolved template/visual chains, and
    /// assemblies with no core geometry.
    var failures = 0
    /// One human-readable reason per failure ("ACHR <id>: <why>") — the 5.6
    /// acceptance rule: every counted failure is explained, so
    /// `failureReasons.count == failures` always.
    var failureReasons: [String] = []
    /// Rendered actors split exactly into animated + bind-pose fallback.
    var animated = 0
    var animationFailures = 0
    var animationFailureReasons: [String] = []
}

/// Assembled actor render data handed to makeScene beside static instances.
nonisolated struct CellActorBuild {
    var placements: [RenderPlacement] = []
    var animations: [any RenderAnimation] = []
    var counts = ActorBuildCounts()
    var durationMS = 0.0
}

extension CellSceneBuilder {
    /// Actors for one exterior cell: local ACHRs plus worldspace-persistent
    /// ACHRs whose physical position lies in this cell, resolved + assembled.
    nonisolated func buildExteriorActors(
        cellChildren: ESMGroup?,
        world: ESMGroup,
        coordinate: CellCoordinate,
        localized: Bool
    ) -> CellActorBuild {
        let started = DispatchTime.now().uptimeNanoseconds
        var build = CellActorBuild()
        var malformed: [String] = []
        var byID: [UInt32: PlacedActor] = [:]
        for actor in decodeActors(in: cellChildren, malformed: &malformed) {
            byID[actor.formID.rawValue] = actor
        }
        for actor in persistentActors(in: world, localized: localized) {
            let owner = CellGridManager.cellCoordinate(for: actor.placement.position)
            guard owner == coordinate else { continue }
            byID[actor.formID.rawValue] = actor
        }
        let actors = byID.values.sorted { $0.formID.rawValue < $1.formID.rawValue }
        build.counts.discovered = actors.count + malformed.count
        build.counts.failures = malformed.count
        build.counts.failureReasons = malformed
        resolveActors(actors, into: &build, localized: localized)
        build.durationMS =
            Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        return build
    }

    /// Actors for one interior cell — local children groups only; interiors
    /// have no worldspace persistent cell to map in.
    nonisolated func buildInteriorActors(
        cellChildren: ESMGroup?,
        localized: Bool
    ) -> CellActorBuild {
        let started = DispatchTime.now().uptimeNanoseconds
        var build = CellActorBuild()
        var malformed: [String] = []
        let actors = decodeActors(in: cellChildren, malformed: &malformed)
        build.counts.discovered = actors.count + malformed.count
        build.counts.failures = malformed.count
        build.counts.failureReasons = malformed
        resolveActors(actors, into: &build, localized: localized)
        build.durationMS =
            Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        return build
    }

    /// Non-deleted ACHRs decoded from the cell's persistent + temporary
    /// children groups. Deleted records place nothing (not discovered);
    /// a decode failure is discovered-but-failed.
    nonisolated private func decodeActors(
        in cellChildren: ESMGroup?,
        malformed: inout [String]
    ) -> [PlacedActor] {
        guard let cellChildren, let children = try? cellChildren.children() else {
            return []
        }
        var actors: [PlacedActor] = []
        for case let .group(group) in children {
            guard
                group.kind == .cellPersistentChildren || group.kind == .cellTemporaryChildren,
                let records = try? group.children()
            else { continue }
            for case let .record(record) in records where record.type == "ACHR" {
                guard !record.isDeleted else { continue }
                do {
                    try actors.append(PlacedActor(record: record))
                } catch {
                    let id = FormID(record.formID).description
                    malformed.append("ACHR \(id): malformed record")
                    Self.logger.warning("malformed ACHR \(id, privacy: .public) counted failed")
                }
            }
        }
        return actors
    }

    /// ACHRs of the worldspace persistent CELL at grid (0,0), cached per
    /// WRLD like exteriorPersistentTeleportRefs. Malformed persistent records
    /// are logged once here — they carry no position, so no streamed cell can
    /// own (or count) them.
    nonisolated private func persistentActors(
        in world: ESMGroup,
        localized: Bool
    ) -> [PlacedActor] {
        let key = world.parentFormID ?? 0
        if let cached = exteriorPersistentActors[key] {
            return cached
        }
        var actors: [PlacedActor] = []
        if let persistent = findCell(in: world, gridX: 0, gridY: 0, localized: localized) {
            var malformed: [String] = []
            actors = decodeActors(in: persistent.children, malformed: &malformed)
        }
        exteriorPersistentActors[key] = actors
        return actors
    }

    /// Resolves each ACHR through the template + visual chains, assembles GPU
    /// assets via MeshLibrary, and buckets every actor exactly once. Per-actor
    /// failures log + count and never abort the build (mod-quirk rule).
    nonisolated private func resolveActors(
        _ actors: [PlacedActor],
        into build: inout CellActorBuild,
        localized: Bool
    ) {
        guard !actors.isEmpty else { return }
        let resolvers = actorResolversBuildingIfNeeded(localized: localized)
        let assembler = ActorAssembler(provider: meshes)
        for actor in actors {
            let id = actor.formID.description
            if actor.isInitiallyDisabled {
                build.counts.disabledSkips += 1
                Self.logger.info("ACHR \(id, privacy: .public): initially disabled, skipped")
                continue
            }
            do {
                let appearance = try resolvers.template.resolve(base: actor.base)
                let visual = try resolvers.visual.resolve(appearance: appearance)
                let assembly = assembler.assemble(placed: actor, visual: visual)
                if assembly.isRenderable {
                    build.counts.rendered += 1
                    build.placements.append(contentsOf: assembly.renderPlacements)
                    switch makeAnimationPlayback(assembly: assembly) {
                    case let .success(playback):
                        build.counts.animated += 1
                        build.animations.append(playback)
                    case let .failure(error):
                        build.counts.animationFailures += 1
                        build.counts.animationFailureReasons.append(
                            "ACHR \(id): \(error.localizedDescription)"
                        )
                    }
                } else {
                    build.counts.failures += 1
                    let reasons = assembly.skips.map { String(describing: $0.reason) }
                        .joined(separator: ", ")
                    build.counts.failureReasons.append(
                        "ACHR \(id): no renderable geometry (\(reasons))"
                    )
                    Self.logger.warning(
                        """
                        ACHR \(id, privacy: .public): no renderable geometry \
                        (\(reasons, privacy: .public)), failed
                        """
                    )
                }
            } catch {
                build.counts.failures += 1
                let reason = String(describing: error)
                build.counts.failureReasons.append("ACHR \(id): unresolved (\(reason))")
                Self.logger.warning(
                    """
                    ACHR \(id, privacy: .public): unresolved \
                    (\(reason, privacy: .public)), failed
                    """
                )
            }
        }
    }

    /// Template + visual resolver pair over the plugin's NPC_/LVLN and
    /// RACE/ARMO/ARMA/OTFT/LVLI top groups, built once and reused across
    /// every cell build (shared like statIndex).
    nonisolated private func actorResolversBuildingIfNeeded(
        localized: Bool
    ) -> (template: ActorTemplateResolver, visual: ActorVisualResolver) {
        if let template = actorTemplateResolver, let visual = actorVisualResolver {
            return (template, visual)
        }
        let template = ActorTemplateResolver.build(from: file, localized: localized)
        let visual = ActorVisualResolver.build(
            from: file, localized: localized, pluginName: pluginName
        )
        actorTemplateResolver = template
        actorVisualResolver = visual
        return (template, visual)
    }
}
