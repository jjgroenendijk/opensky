// Per-cell trigger volumes, kept apart from the static collision hot path.
// Two sources feed one `TriggerVolumeSet`: SkyrimLayer 12 bodies in placed NIFs,
// which the static build drops, and `XPRM` primitives on the REFR itself
// (docs/formats/placed-references.md). Both run in the same build-queue call.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyWorldState
import simd

/// Both immutable collision products of one cell build. They are produced
/// together because they share the same reference list and the same NIF cache,
/// and travel together onto the `CellScene`.
nonisolated public struct CellCollisionBuild: Sendable {
    public let staticCollision: StaticCollisionSet
    public let triggerVolumes: TriggerVolumeSet
    /// Bodies of this cell the dynamic world simulates. Empty for a build with
    /// no reference retention, because a simulated body needs the
    /// `ReferenceKey` the entries carry.
    public var dynamicBodies: [DynamicBodyPlacement] = []
}

nonisolated extension CellSceneBuilder {
    /// The solid set and the trigger set for one cell, from the references a
    /// build settled on after runtime state was applied.
    nonisolated public func buildCollision(
        resolved: EffectiveReferences,
        location: CellSceneLocation
    ) -> CellCollisionBuild {
        loadPhases.measure(.collision) {
            let products = buildCollisionProducts(
                refs: resolved.references,
                location: location,
                keys: resolved.entries.reduce(into: [:]) { keys, entry in
                    keys[entry.formID] = entry.key
                }
            )
            return CellCollisionBuild(
                staticCollision: products.collision,
                triggerVolumes: buildTriggerVolumes(
                    refs: resolved.references, entries: resolved.entries, location: location
                ),
                dynamicBodies: products.dynamicBodies
            )
        }
    }

    /// Every authored trigger volume of one cell, primitives first, then mesh
    /// bodies, each in reference order. `refs` has runtime deltas applied; a
    /// reference with no `entries` key names nothing, so it is counted and skipped.
    nonisolated public func buildTriggerVolumes(
        refs: [PlacedReference],
        entries: [RuntimeReferenceEntry],
        location: CellSceneLocation
    ) -> TriggerVolumeSet {
        guard !refs.isEmpty else {
            return TriggerVolumeSet(location: location, volumes: [])
        }
        var keys: [FormID: ReferenceKey] = [:]
        keys.reserveCapacity(entries.count)
        for entry in entries {
            keys[entry.formID] = entry.key
        }
        var stats = TriggerVolumeStats()
        var volumes = primitiveTriggerVolumes(refs: refs, keys: keys, stats: &stats)
        volumes += meshTriggerVolumes(refs: refs, keys: keys, stats: &stats)
        return TriggerVolumeSet(location: location, volumes: volumes, stats: stats)
    }

    // MARK: - XPRM primitives

    /// Volumes authored on the REFR as an `XPRM` primitive. The half-extents are
    /// pre-scale and local, so the `MatrixMath.placement` matrix carries pose and
    /// scale with the same Euler convention as the collision placements.
    nonisolated private func primitiveTriggerVolumes(
        refs: [PlacedReference],
        keys: [FormID: ReferenceKey],
        stats: inout TriggerVolumeStats
    ) -> [TriggerVolume] {
        var volumes: [TriggerVolume] = []
        for ref in refs {
            guard let primitive = ref.primitive else { continue }
            // A room marker's box is occlusion data, like a portal box.
            guard ref.details.room == nil, let geometry = Self.triggerGeometry(of: primitive) else {
                stats.excludedPrimitiveCount += 1
                continue
            }
            guard let key = keys[ref.formID] else {
                stats.unkeyedReferenceCount += 1
                continue
            }
            let placed = TriggerVolume.placed(
                reference: key,
                formID: ref.formID,
                transform: MatrixMath.placement(
                    position: ref.placement.position,
                    rotation: ref.placement.rotation,
                    scale: ref.scale
                ),
                geometry: geometry
            )
            guard let placed else {
                stats.degenerateVolumeCount += 1
                continue
            }
            volumes.append(placed)
            stats.primitiveVolumeCount += 1
        }
        return volumes
    }

    /// The geometry an `XPRM` primitive stands for. Only `box` and `sphere` are
    /// gameplay triggers; the rest are counted exclusions
    /// (docs/engine/trigger-volumes.md). A sphere's radius is `halfExtents.x`:
    /// all 137 spheres in `Skyrim.esm` store one value on every axis.
    nonisolated public static func triggerGeometry(
        of primitive: PlacedReference.Primitive
    ) -> NIFCollisionGeometry? {
        switch primitive.type {
        case .box:
            .box(halfExtents: primitive.halfExtents)
        case .sphere:
            .sphere(radius: primitive.halfExtents.x)
        case .none, .portalBox, .line:
            nil
        }
    }

    // MARK: - Layer 12 NIF bodies

    /// Trigger volumes from the SkyrimLayer 12 bodies of the cell's placed
    /// NIFs. Models come from the same build-queue-confined
    /// `NIFCollisionLibrary` cache the static build already populated, so this
    /// pass decodes nothing a second time.
    nonisolated private func meshTriggerVolumes(
        refs: [PlacedReference],
        keys: [FormID: ReferenceKey],
        stats: inout TriggerVolumeStats
    ) -> [TriggerVolume] {
        guard let collisionModels else { return [] }
        var volumes: [TriggerVolume] = []
        for placement in resolveCollisionPlacements(refs: refs) {
            // The static pass already counted this model's load failure.
            guard let model = try? collisionModels.model(path: placement.modelPath) else {
                continue
            }
            guard model.bodies.contains(where: \.isTriggerVolume) else { continue }
            guard let key = keys[placement.reference] else {
                stats.unkeyedReferenceCount += 1
                continue
            }
            for body in model.bodies where body.isTriggerVolume {
                for shape in body.shapes {
                    let placed = TriggerVolume.placed(
                        reference: key,
                        formID: placement.reference,
                        transform: placement.transform * body.transform * shape.transform,
                        geometry: shape.geometry
                    )
                    guard let placed else {
                        stats.degenerateVolumeCount += 1
                        continue
                    }
                    volumes.append(placed)
                    stats.meshVolumeCount += 1
                }
            }
        }
        return volumes
    }
}
