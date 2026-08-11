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
    /// Actors present but deliberately not drawn: initially-disabled ACHRs
    /// (record-header flag 0x800), plus the ones runtime state disabled or
    /// deleted since load (issue #160). All three share one bucket so the
    /// exact-accounting rule above keeps holding; the per-actor log line says
    /// which of them applied.
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
    /// Every `AppearanceSkip` the visual resolution reported, per actor, as
    /// "ACHR <id>: <reason> (<subject>)" (issue #180).
    ///
    /// Not an error bucket and deliberately outside the exact-accounting
    /// identity above: an actor whose skin torso is masked by its equipped
    /// cuirass renders perfectly and still reports a skip. The list exists so
    /// the `World > Inventory & Equipment` panel can say why a piece of an
    /// equipped set contributed no geometry, instead of leaving a missing
    /// gauntlet looking like an equip that silently did nothing.
    var appearanceSkipReasons: [String] = []
}

/// Assembled actor render data handed to makeScene beside static instances.
nonisolated struct CellActorBuild {
    var placements: [RenderPlacement] = []
    var animations: [any RenderAnimation] = []
    var counts = ActorBuildCounts()
    var durationMS = 0.0
    /// Runtime index entries for the ACHRs this cell owns (issue #158).
    /// Populated for every discovered actor, including ones skipped for
    /// rendering: an initially-disabled actor still exists at runtime.
    var entries: [RuntimeReferenceEntry] = []
}

nonisolated extension CellSceneBuilder {
    /// Actors for one exterior cell: local ACHRs plus worldspace-persistent
    /// ACHRs whose physical position lies in this cell, resolved + assembled.
    nonisolated func buildExteriorActors(
        cellChildren: ESMGroup?,
        world: ESMGroup,
        coordinate: CellCoordinate,
        localized: Bool,
        deltas: [ReferenceKey: ReferenceStateDelta] = [:]
    ) -> CellActorBuild {
        let started = DispatchTime.now().uptimeNanoseconds
        var build = CellActorBuild()
        var malformed: [String] = []
        var byID: [UInt32: CollectedActor] = [:]
        for collected in decodeActors(in: cellChildren, malformed: &malformed) {
            byID[collected.actor.formID.rawValue] = collected
        }
        // Records stored in the worldspace persistent CELL are persistent by
        // definition, whichever children group inside it holds them.
        for actor in persistentActors(in: world, localized: localized) {
            let owner = CellGridManager.cellCoordinate(for: actor.placement.position)
            guard owner == coordinate else { continue }
            byID[actor.formID.rawValue] = CollectedActor(actor: actor, isPersistent: true)
        }
        let collected = byID.values.sorted { $0.actor.formID.rawValue < $1.actor.formID.rawValue }
        let actors = collected.map(\.actor)
        build.entries = actorEntries(collected)
        build.counts.discovered = actors.count + malformed.count
        build.counts.failures = malformed.count
        build.counts.failureReasons = malformed
        resolveActors(actors, into: &build, localized: localized, deltas: deltas)
        build.durationMS =
            Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        return build
    }

    /// Actors for one interior cell — local children groups only; interiors
    /// have no worldspace persistent cell to map in.
    nonisolated func buildInteriorActors(
        cellChildren: ESMGroup?,
        localized: Bool,
        deltas: [ReferenceKey: ReferenceStateDelta] = [:]
    ) -> CellActorBuild {
        let started = DispatchTime.now().uptimeNanoseconds
        var build = CellActorBuild()
        var malformed: [String] = []
        let collected = decodeActors(in: cellChildren, malformed: &malformed)
        let actors = collected.map(\.actor)
        build.entries = actorEntries(collected)
        build.counts.discovered = actors.count + malformed.count
        build.counts.failures = malformed.count
        build.counts.failureReasons = malformed
        resolveActors(actors, into: &build, localized: localized, deltas: deltas)
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
    ) -> [CollectedActor] {
        guard let cellChildren, let children = try? cellChildren.children() else {
            return []
        }
        var actors: [CollectedActor] = []
        for case let .group(group) in children {
            guard
                group.kind == .cellPersistentChildren || group.kind == .cellTemporaryChildren,
                let records = try? group.children()
            else { continue }
            let isPersistent = group.kind == .cellPersistentChildren
            for case let .record(record) in records where record.type == "ACHR" {
                guard !record.isDeleted else { continue }
                do {
                    try actors.append(CollectedActor(
                        actor: PlacedActor(record: record), isPersistent: isPersistent
                    ))
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
                .map(\.actor)
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
        localized: Bool,
        deltas: [ReferenceKey: ReferenceStateDelta]
    ) {
        guard !actors.isEmpty else { return }
        let resolvers = actorResolversBuildingIfNeeded(localized: localized)
        let assembler = ActorAssembler(provider: meshes)
        let indexed = entriesByFormID(build.entries)
        for actor in actors {
            let id = actor.formID.description
            if
                let skip = actorRuntimeSkip(
                    actor: actor, entry: indexed[actor.formID], deltas: deltas
                )
            {
                build.counts.disabledSkips += 1
                Self.logger.info("ACHR \(id, privacy: .public): \(skip, privacy: .public), skipped")
                continue
            }
            do {
                let appearance = try resolvers.template.resolve(base: actor.base)
                let visual = try resolvers.visual.resolve(
                    appearance: appearance,
                    equipped: runtimeEquipment(
                        entry: indexed[actor.formID], deltas: deltas
                    )
                )
                let placed = actorApplyingRuntimeTransform(
                    actor,
                    entry: indexed[actor.formID],
                    deltas: deltas
                )
                record(
                    assembler.assemble(placed: placed, visual: visual),
                    id: id,
                    into: &build
                )
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

    nonisolated private func actorApplyingRuntimeTransform(
        _ actor: PlacedActor,
        entry: RuntimeReferenceEntry?,
        deltas: [ReferenceKey: ReferenceStateDelta]
    ) -> PlacedActor {
        guard
            let entry,
            let transform = deltas[entry.key]?.component(ReferenceTransformOverride.self)
        else { return actor }
        return PlacedActor(
            copying: actor,
            placement: transform.placement,
            scale: transform.scale
        )
    }

    /// Buckets one assembled actor: drawn plus its animation outcome, or a
    /// counted failure with its reason. Split out of `resolveActors` so both
    /// stay inside the strict-lint function-body cap.
    nonisolated private func record(
        _ assembly: ActorAssembly<ActorRenderAsset>,
        id: String,
        into build: inout CellActorBuild
    ) {
        build.counts.appearanceSkipReasons += Self.appearanceSkipLines(assembly, id: id)
        guard assembly.isRenderable else {
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
            return
        }
        build.counts.rendered += 1
        let faceMorph = makeFaceMorphPlayback(assembly: assembly)
        build.placements.append(contentsOf: assembly.renderPlacements(
            at: assembly.transform,
            faceMorphs: faceMorph?.bindings ?? [:]
        ))
        if let faceMorph {
            build.animations.append(faceMorph)
        }
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
    }

    /// The assembly's `AppearanceSkip` entries as readable lines, one per skip.
    ///
    /// Only the `.appearance` subject is taken: the other `ActorAssemblySkip`
    /// subjects are asset-loading outcomes, which the failure buckets above
    /// already own, and mixing the two would make a missing NIF read as a
    /// resolution decision.
    nonisolated private static func appearanceSkipLines(
        _ assembly: ActorAssembly<ActorRenderAsset>,
        id: String
    ) -> [String] {
        assembly.skips.compactMap { skip in
            guard case let .appearance(appearance) = skip.subject else { return nil }
            return "ACHR \(id): \(appearance.reason) (\(appearance.subject))"
        }
    }

    /// The equipped set a dirty actor renders from, or nil when nothing has
    /// touched its inventory and the plugin `defaultOutfit` still describes it
    /// (issue #178).
    ///
    /// The component is the whole answer: `InventoryBaselineResolver` baselines
    /// an actor's equipped set to its default outfit, so the first equip
    /// materializes the outfit *and* the new piece together and this override
    /// never undresses an actor by accident.
    nonisolated private func runtimeEquipment(
        entry: RuntimeReferenceEntry?,
        deltas: [ReferenceKey: ReferenceStateDelta]
    ) -> [FormID]? {
        guard let entry, let delta = deltas[entry.key] else { return nil }
        return delta.component(ReferenceInventoryState.self)?.equipped
    }

    /// Why this actor is not drawn, or nil when it should be.
    ///
    /// The record's initially-disabled flag and the runtime enable/deletion
    /// components resolve through the one `ReferenceState` path (issue #160),
    /// so a script that enables a hidden actor makes it appear, and one that
    /// disables or deletes a visible actor makes it vanish. An actor with no
    /// index entry has no runtime identity, so only its record flag applies.
    nonisolated private func actorRuntimeSkip(
        actor: PlacedActor,
        entry: RuntimeReferenceEntry?,
        deltas: [ReferenceKey: ReferenceStateDelta]
    ) -> String? {
        guard let entry else {
            return actor.isInitiallyDisabled ? "initially disabled" : nil
        }
        let resolved = resolvedRuntimeState(for: entry, deltas: deltas)
        guard !resolved.isVisible else { return nil }
        if resolved.deletion.isDeleted {
            return "deleted at runtime"
        }
        return resolved.overriddenKinds.contains(.enableState)
            ? "disabled at runtime"
            : "initially disabled"
    }

    /// Template + visual resolver pair over the plugin's NPC_/LVLN and
    /// RACE/ARMO/ARMA/OTFT/LVLI top groups, built once and reused across
    /// every cell build (shared like statIndex). Internal rather than private
    /// because the player body resolves through the same pair
    /// (CellSceneBuilderPlayer.swift) and must not force a second copy of two
    /// plugin-wide indexes into memory.
    nonisolated func actorResolversBuildingIfNeeded(
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
