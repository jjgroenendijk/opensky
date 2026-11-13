// Resolves each placed actor to its visual, state, and equipment.

import Foundation
import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyTerrain
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

nonisolated extension CellSceneBuilder.CellActorResolver {
    /// Resolves each ACHR through the template + visual chains, assembles GPU
    /// assets via MeshLibrary, and buckets every actor exactly once. Per-actor
    /// failures log + count and never abort the build (mod-quirk rule).
    nonisolated func resolveActors(
        _ actors: [PlacedActor],
        into build: inout CellActorBuild,
        deltas: [ReferenceKey: ReferenceStateDelta],
        enable: EnableParentResolver
    ) {
        guard !actors.isEmpty else { return }
        let indexed = owner.referenceBuilder.states.entriesByFormID(build.entries)
        let steps = actors.map { actor in
            resolveStep(actor, entry: indexed[actor.formID], deltas: deltas, enable: enable)
        }
        // Every look is known before the first assembly, so the part files load on every core.
        owner.meshes.preparse(paths: steps.flatMap(\.modelPaths))
        defer { owner.meshes.dropPreparsed() }
        let assembler = ActorAssembler(provider: owner.meshes)
        for (actor, step) in zip(actors, steps) {
            let id = actor.formID.description
            switch step {
            case let .skipped(skip, key):
                build.counts.disabledSkips += 1
                if let key {
                    build.disabledKeys.insert(key)
                }
                CellSceneBuilder.logger
                    .info("ACHR \(id, privacy: .public): \(skip, privacy: .public), skipped")
            case let .resolved(placed, visual, head):
                owner.actorBuilder.recorder.record(
                    assembler.assemble(placed: placed, visual: visual),
                    id: id,
                    into: &build
                )
                if let head {
                    owner.actorBuilder.recorder.recordSeveredHead(
                        assembler.assemble(placed: placed, visual: head), into: &build
                    )
                }
            case let .failed(reason):
                build.counts.failures += 1
                build.counts.failureReasons.append("ACHR \(id): unresolved (\(reason))")
                CellSceneBuilder.logger.warning(
                    """
                    ACHR \(id, privacy: .public): unresolved \
                    (\(reason, privacy: .public)), failed
                    """
                )
            }
        }
    }

    /// The runtime skip, or the resolved look, of one actor. Reads records only.
    nonisolated private func resolveStep(
        _ actor: PlacedActor,
        entry: RuntimeReferenceEntry?,
        deltas: [ReferenceKey: ReferenceStateDelta],
        enable: EnableParentResolver
    ) -> ActorBuildStep {
        if let skip = actorRuntimeSkip(actor: actor, entry: entry, deltas: deltas, enable: enable) {
            return .skipped(skip, entry?.key)
        }
        let resolvers = actorResolversBuildingIfNeeded()
        do {
            let roll = entry.map {
                owner.referenceBuilder.leveledRoll(of: $0.key, base: actor.base, deltas: deltas)
            }
            let templates = resolvers.template.rolling(roll)
            let appearance = try templates.resolve(base: actor.base)
            var visual = try resolvers.visual.resolve(
                appearance: appearance,
                equipped: runtimeEquipment(entry: entry, deltas: deltas),
                roll: roll,
                carried: templates.carriedItems(base: actor.base)
            ).presenting(
                entry.flatMap { deltas[$0.key]?.component(ActorPresentationState.self) },
                textureSets: resolvers.visual.textureSets
            )
            if
                visual.headSource == .assembled,
                let face = PlayerAppearanceOverride(face: appearance)
            {
                visual = owner.actorBuilder.chargen.chargenVisual(visual, appearance: face)
            }
            let placed = actorApplyingRuntimeTransform(actor, entry: entry, deltas: deltas)
            let death = entry.flatMap { deltas[$0.key]?.component(ActorDeathState.self) }
            guard death?.severedNode != nil else { return .resolved(placed, visual, head: nil) }
            let cut = visual.decapitated(gore: resolvers.visual.decapitationGore(for: visual))
            return .resolved(placed, cut.body, head: cut.head)
        } catch {
            return .failed(String(describing: error))
        }
    }

    /// Template + visual resolver pair over the plugin's NPC_/LVLN and
    /// RACE/ARMO/ARMA/OTFT/LVLI top groups, built once and reused across
    /// every cell build (shared like statIndex). Internal rather than private
    /// because the player body resolves through the same pair
    /// (CellSceneBuilderPlayer.swift) and must not force a second copy of two
    /// plugin-wide indexes into memory.
    nonisolated func actorResolversBuildingIfNeeded()
        -> (template: ActorTemplateResolver, visual: ActorVisualResolver)
    {
        if let template = owner.actorTemplateResolver, let visual = owner.actorVisualResolver {
            return (template, visual)
        }
        let loadOrder = owner.recordIndex.loadOrderIndexBuildingIfNeeded().loadOrder
        let (template, visual) = owner.loadPhases.measure(.actorIndex) {
            (
                ActorTemplateResolver.build(from: loadOrder, leveling: owner.leveling),
                ActorVisualResolver.build(from: loadOrder, leveling: owner.leveling)
            )
        }
        owner.actorTemplateResolver = template
        owner.actorVisualResolver = visual
        return (template, visual)
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
        let resolved = owner.referenceBuilder.states.resolvedRuntimeState(
            for: entry,
            deltas: deltas
        )
        if resolved.deletion.isDeleted {
            return "deleted at runtime"
        }
        guard !enable.isEnabled(entry) else { return nil }
        return resolved.overriddenKinds.contains(.enableState)
            ? "disabled at runtime"
            : "initially disabled"
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
}
