// The doors and interactions a scene offers the player.

import Foundation
import OpenSkyCrimeInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyObjectAnimation
import OpenSkyPhysics
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyTerrain
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

nonisolated extension CellSceneBuilder.CellSceneInteractions {
    /// Keeps only REFRs whose base resolves to DOOR and whose XTEL decoded.
    /// Interaction metadata independently includes non-teleport doors.
    nonisolated func resolveDoors(refs: [PlacedReference]) -> [PlacedDoor] {
        let modelBaseIndex = owner.modelIndex.modelBaseIndexBuildingIfNeeded()
        return refs.compactMap { ref in
            guard
                modelBaseIndex[ref.base.rawValue]?.recordType == "DOOR",
                let destination = ref.teleportDestination
            else { return nil }
            return PlacedDoor(
                reference: ref.formID,
                position: ref.placement.position,
                destination: destination
            )
        }
    }

    /// Retains named use-key targets beside collision geometry. Every
    /// interaction-capable base uses the generic activation action except
    /// doors, whose typed open action can additionally drive XTEL.
    nonisolated func resolveInteractions(
        refs: [PlacedReference]
    ) -> [FormID: PlacedInteraction] {
        let modelBaseIndex = owner.modelIndex.modelBaseIndexBuildingIfNeeded()
        var interactions: [FormID: PlacedInteraction] = [:]
        for ref in refs {
            guard
                let base = modelBaseIndex[ref.base.rawValue],
                base.allowsManualInteraction || base.isAutomaticDoor,
                let action = interactionAction(for: base.recordType)
            else { continue }
            let override = resolvedText(base.activateTextOverride)
                .flatMap { $0.isEmpty ? nil : $0 }
            let name = resolvedText(base.name)
                .flatMap { $0.isEmpty ? nil : $0 }
            let seats = base.recordType == "FURN" ? owner.objectBuilder
                .seats(of: base, at: ref) : []
            // The game's verbs are string settings; `ActivationPrompt` lays them on at run time.
            let isBed = seats.contains { $0.animationType == FurnitureSeat.sleepAnimation }
            var interaction = PlacedInteraction(
                reference: ref.formID,
                base: ref.base,
                position: ref.placement.position,
                name: ref.teleportDestination.flatMap { destinationName(door: $0.door) }
                    ?? name ?? base.editorID ?? base.formID.description,
                action: action,
                actionLabel: override ?? (isBed ? "Sleep" : action.defaultLabel),
                sounds: base.sounds,
                voiceType: base.voiceType,
                station: base.workbench.map {
                    CraftingStation(workbench: $0, keywords: base.keywords.keywords)
                },
                produce: base.produce,
                lock: action == .open || action == .search ? ref.lock : nil
            )
            interaction.seats = seats
            interaction.hasLabelOverride = override != nil
            // XAPD: only an activate parent or a script may activate the reference.
            interaction.parentActivateOnly = ref.details.parentActivateOnly == true
            if base.isAutomaticDoor {
                let area = interaction.parentActivateOnly
                    ? nil : Self.automaticArea(of: base, at: ref)
                guard let area else { continue }
                interaction.automaticArea = area
            }
            interactions[ref.formID] = interaction
        }
        return interactions
    }

    nonisolated private func interactionAction(
        for recordType: FourCC
    ) -> InteractionAction? {
        switch recordType {
        case "DOOR":
            .open
        case "ACTI":
            .activate
        case "CONT":
            .search
        case "TREE", "FLOR":
            .harvest
        case "TACT":
            .talk
        case "FURN":
            .use
        default:
            ModelBase.itemTypes.contains(recordType) ? .take : nil
        }
    }

    /// An automatic door without bounds covers no space, so it is left out.
    nonisolated private static func automaticArea(
        of base: ModelBase, at ref: PlacedReference
    ) -> AutomaticDoorArea? {
        guard let bounds = base.details.bounds, !bounds.isEmpty else { return nil }
        let transform = MatrixMath.placement(
            position: ref.placement.position, rotation: ref.placement.rotation, scale: ref.scale
        )
        return AutomaticDoorArea(
            worldToLocal: transform.inverse,
            minimum: SIMD3<Float>(bounds.minimum),
            maximum: SIMD3<Float>(bounds.maximum)
        )
    }

    /// A load door shows where it leads: the interior cell's name, or else the name of
    /// the worldspace that holds the far door.
    nonisolated private func destinationName(door: FormID) -> String? {
        let index = owner.recordIndex.loadOrderIndexBuildingIfNeeded()
        let cell = index.cellFormID(containing: door)
            .flatMap { index.record(withFormID: $0) }
            .flatMap { found in
                found.record.type == "CELL"
                    ? attempt { try Cell(record: found.record, localized: found.localized) } : nil
            }
        let world = index.worldFormID(containing: door)
            .flatMap { owner.waterBuilder.worldspaceIndexBuildingIfNeeded()[$0.rawValue] }
        return LoadDoorName.resolve(
            cellName: cell.flatMap { resolvedText($0.name) },
            isInterior: cell?.isInterior == true,
            worldspaceName: world.flatMap { resolvedText($0.name) }
        )
    }

    nonisolated private func resolvedText(_ text: LString?) -> String? {
        if case let .inline(value) = text {
            return value
        }
        return owner.localizedStrings?.resolve(text)
    }
}
