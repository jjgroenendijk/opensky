// ACHR actors build and evict with their cell on the build queue. Worldspace-
// persistent ACHRs live under the worldspace persistent CELL and map into cells
// by position. Per cell: discovered = rendered + intentional skips + failures.
// Resolution documented in docs/engine/actor-resolution.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyRendering
import OpenSkyWorldState
import simd

/// Per-build actor accounting; folded into CellLoadSummary. The exact
/// invariant `discovered == rendered + disabledSkips + failures` is the 5.5
/// acceptance rule — every discovered ACHR must land in exactly one bucket.
nonisolated public struct ActorBuildCounts: Sendable {
    /// Non-deleted ACHRs owned by this cell: local persistent + temporary
    /// children plus position-mapped worldspace-persistent placements.
    public var discovered = 0
    public var rendered = 0
    /// Actors present but deliberately not drawn: initially-disabled ACHRs
    /// (record flag 0x800) and ones runtime state disabled or deleted. One
    /// bucket keeps the accounting rule above; the log line says which applied.
    public var disabledSkips = 0
    /// Malformed ACHR records, unresolved template/visual chains, and
    /// assemblies with no core geometry.
    public var failures = 0
    /// One human-readable reason per failure ("ACHR <id>: <why>") — the 5.6
    /// acceptance rule: every counted failure is explained, so
    /// `failureReasons.count == failures` always.
    public var failureReasons: [String] = []
    /// Rendered actors split exactly into animated + bind-pose fallback.
    public var animated = 0
    public var animationFailures = 0
    public var animationFailureReasons: [String] = []
    /// Every `AppearanceSkip`, per actor, as "ACHR <id>: <reason> (<subject>)".
    /// Not an error: a masked skin torso still reports one. The inventory panel
    /// uses it to say why an equipped piece drew nothing.
    public var appearanceSkipReasons: [String] = []
    /// Each drawn humanoid's head parts and the head it shows, by ACHR.
    public var heads: [FormID: ActorHeadReadout] = [:]
}

/// Assembled actor render data handed to makeScene beside static instances.
nonisolated public struct CellActorBuild {
    public var placements: [RenderPlacement] = []
    public var animations: [any RenderAnimation] = []
    public var counts = ActorBuildCounts()
    public var durationMS = 0.0
    /// Runtime index entries for every ACHR this cell owns, including ones not
    /// drawn: an initially-disabled actor still exists at runtime.
    public var entries: [RuntimeReferenceEntry] = []
    /// Actors that exist but are disabled: the AI, the HUD, and the agent skip them.
    public var disabledKeys: Set<ReferenceKey> = []
}

/// What an actor's `XESP` link may name besides the cell's own actors.
nonisolated public struct ActorEnableParents {
    public var references: [FormID: RuntimeReferenceEntry]
    public var pool: EnableParentPool

    public init(
        references: [FormID: RuntimeReferenceEntry] = [:],
        pool: EnableParentPool = EnableParentPool()
    ) {
        self.references = references
        self.pool = pool
    }
}

nonisolated extension CellSceneBuilder {
    /// Actors for one exterior cell: local ACHRs plus worldspace-persistent
    /// ACHRs whose physical position lies in this cell, resolved + assembled.
    nonisolated public func buildExteriorActors(
        cell: FoundCell?,
        world: FoundWorld,
        coordinate: CellCoordinate,
        localized: Bool,
        deltas: [ReferenceKey: ReferenceStateDelta] = [:],
        parents: ActorEnableParents = ActorEnableParents()
    ) -> CellActorBuild {
        let started = DispatchTime.now().uptimeNanoseconds
        var malformed: [String] = []
        var byID: [UInt32: CollectedActor] = [:]
        for collected in decodeActors(in: cell, malformed: &malformed) {
            byID[collected.actor.formID.rawValue] = collected
        }
        // Records stored in the worldspace persistent CELL are persistent by
        // definition, whichever children group inside it holds them.
        for actor in persistentActors(in: world, localized: localized) {
            let owner = CellGridManager.cellCoordinate(for: actor.placement.position)
            guard owner == coordinate else { continue }
            byID[actor.formID.rawValue] = CollectedActor(actor: actor, isPersistent: true)
        }
        let collected = relocating(
            byID.values.sorted { $0.actor.formID.rawValue < $1.actor.formID.rawValue },
            into: .exterior(coordinate),
            deltas: deltas
        )
        return resolvedBuild(
            collected, malformed: malformed, parents: parents, deltas: deltas, started: started
        )
    }

    /// Actors for one interior cell — local children groups only; interiors
    /// have no worldspace persistent cell to map in.
    nonisolated public func buildInteriorActors(
        cell: FoundCell?,
        location: CellSceneLocation,
        localized _: Bool,
        deltas: [ReferenceKey: ReferenceStateDelta] = [:],
        parents: ActorEnableParents = ActorEnableParents()
    ) -> CellActorBuild {
        let started = DispatchTime.now().uptimeNanoseconds
        var malformed: [String] = []
        let collected = relocating(
            decodeActors(in: cell, malformed: &malformed), into: location, deltas: deltas
        )
        return resolvedBuild(
            collected, malformed: malformed, parents: parents, deltas: deltas, started: started
        )
    }

    /// Counts, indexes, and resolves the collected actors of one cell build.
    nonisolated private func resolvedBuild(
        _ collected: [CollectedActor],
        malformed: [String],
        parents: ActorEnableParents,
        deltas: [ReferenceKey: ReferenceStateDelta],
        started: UInt64
    ) -> CellActorBuild {
        var build = CellActorBuild()
        let actors = collected.map(\.actor)
        build.entries = actorEntries(collected)
        build.counts.discovered = actors.count + malformed.count
        build.counts.failures = malformed.count
        build.counts.failureReasons = malformed
        let enable = enableResolver(
            entries: parents.references.merging(entriesByFormID(build.entries)) { $1 },
            pool: parents.pool, deltas: deltas
        )
        resolveActors(actors, into: &build, deltas: deltas, enable: enable)
        build.durationMS =
            Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        return build
    }

    /// Non-deleted ACHRs of every plugin from the cell's persistent + temporary
    /// children groups. Deleted records place nothing (not discovered);
    /// a decode failure is discovered-but-failed.
    nonisolated private func decodeActors(
        in cell: FoundCell?,
        malformed: inout [String]
    ) -> [CollectedActor] {
        guard let cell else { return [] }
        let base = decodeBaseActors(in: cell.children, malformed: &malformed)
        return mergingLaterActors(base, cell: FormID(cell.formID), malformed: &malformed)
    }

    nonisolated private func decodeBaseActors(
        in cellChildren: ESMGroup?,
        malformed: inout [String]
    ) -> [CollectedActor] {
        guard let cellChildren, let children = childrenOrSkip(cellChildren) else {
            return []
        }
        var actors: [CollectedActor] = []
        for case let .group(group) in children {
            guard
                group.kind == .cellPersistentChildren || group.kind == .cellTemporaryChildren,
                let records = childrenOrSkip(group)
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

    /// ACHRs of the worldspace persistent CELL, cached per WRLD like
    /// exteriorPersistentRefs. Malformed persistent records are logged once
    /// here — they carry no position, so no streamed cell can own (or count) them.
    nonisolated func persistentActors(
        in world: FoundWorld,
        localized: Bool
    ) -> [PlacedActor] {
        let key = world.formID.rawValue
        if let cached = exteriorPersistentActors[key] {
            return cached
        }
        var actors: [PlacedActor] = []
        if let persistent = persistentCell(in: world, localized: localized) {
            var malformed: [String] = []
            actors = decodeActors(in: persistent, malformed: &malformed)
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
        deltas: [ReferenceKey: ReferenceStateDelta],
        enable: EnableParentResolver
    ) {
        guard !actors.isEmpty else { return }
        let resolvers = actorResolversBuildingIfNeeded()
        let assembler = ActorAssembler(provider: meshes)
        let indexed = entriesByFormID(build.entries)
        for actor in actors {
            let id = actor.formID.description
            if
                let skip = actorRuntimeSkip(
                    actor: actor, entry: indexed[actor.formID], deltas: deltas, enable: enable
                )
            {
                build.counts.disabledSkips += 1
                if let key = indexed[actor.formID]?.key {
                    build.disabledKeys.insert(key)
                }
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
                ).presenting(indexed[actor.formID].flatMap {
                    deltas[$0.key]?.component(ActorPresentationState.self)
                })
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
        if assembly.visual.faceGenMeshPath != nil || !assembly.visual.headParts.parts.isEmpty {
            build.counts.heads[assembly.actor] = ActorHeadReadout(assembly: assembly)
        }
        let faceMorph = makeFaceMorphPlayback(assembly: assembly)
        build.placements.append(contentsOf: assembly.renderPlacements(
            at: assembly.transform,
            faceMorphs: faceMorph?.bindings ?? [:],
            owner: assembly.actor.rawValue
        ))
        if let faceMorph {
            build.animations.append(faceMorph)
            build.animations.append(LipSyncPlayback(faceMorph: faceMorph))
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

    /// The equipped set a changed actor renders from, or nil while its default
    /// outfit still applies. The baseline is the outfit, so the first equip
    /// keeps the outfit and adds the new piece.
    nonisolated private func runtimeEquipment(
        entry: RuntimeReferenceEntry?,
        deltas: [ReferenceKey: ReferenceStateDelta]
    ) -> [FormID]? {
        guard let entry, let delta = deltas[entry.key] else { return nil }
        return delta.component(ReferenceInventoryState.self)?.equipped
    }

    /// Why this actor is not drawn, or nil when it should be. An `XESP` parent
    /// decides alone, as for references; an actor with no index entry only has
    /// its record flag.
    nonisolated private func actorRuntimeSkip(
        actor: PlacedActor,
        entry: RuntimeReferenceEntry?,
        deltas: [ReferenceKey: ReferenceStateDelta],
        enable: EnableParentResolver
    ) -> String? {
        guard let entry else {
            return actor.isInitiallyDisabled ? "initially disabled" : nil
        }
        let resolved = resolvedRuntimeState(for: entry, deltas: deltas)
        if resolved.deletion.isDeleted {
            return "deleted at runtime"
        }
        guard !enable.isEnabled(entry) else { return nil }
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
    nonisolated public func actorResolversBuildingIfNeeded()
        -> (template: ActorTemplateResolver, visual: ActorVisualResolver)
    {
        if let template = actorTemplateResolver, let visual = actorVisualResolver {
            return (template, visual)
        }
        let loadOrder = loadOrderIndexBuildingIfNeeded().loadOrder
        let template = ActorTemplateResolver.build(from: loadOrder)
        let visual = ActorVisualResolver.build(from: loadOrder)
        actorTemplateResolver = template
        actorVisualResolver = visual
        return (template, visual)
    }
}
