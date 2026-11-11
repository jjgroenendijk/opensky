// The references a package act resolves: targets, nearby placed references, and shouts.

import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyDialogueInterface
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWorld
public import OpenSkyWorldInterface
public import OpenSkyWorldState
import simd

extension AIPackageActsAdapter {
    public var references: References {
        References(game: game, packageMoves: packageMoves)
    }

    public struct References {
        let game: any AIPackageActsHost
        let packageMoves: AIPackageMovesAdapter

        public func packageReference(
            _ target: Package.Target, actor: ReferenceKey, aliasQuest: FormID?
        ) -> ReferenceKey? {
            if
                let key = packageMoves.places
                    .packageTargetKey(target, aliasQuest: aliasQuest)
            {
                return key
            }
            switch target.kind {
            case .linkedReference:
                let entry = game.streamer.referenceEntry(key: actor)
                let links = entry?.placedReference?.linkedReferences
                    ?? entry?.placedActor?.details.linkedReferences ?? []
                let keyword = FormID(target.value).nonNull
                return links.first { $0.keyword == keyword }.flatMap { resolveForm($0.ref) }
            case .objectID:
                let position = packageMoves.packageActorPosition(actor) ?? .zero
                return nearest(to: position, within: .infinity) {
                    ConditionFunctions.baseForm(of: $0) == FormID(target.value)
                }
            default:
                return nil
            }
        }

        private func resolveForm(_ formID: FormID) -> ReferenceKey? {
            guard let resolver = game.scripts.bridge?.formIDResolver else { return nil }
            return ReferenceKey.resolve(formID, using: resolver)
        }

        /// The form a selector names by its object ID, such as a spell.
        func selectedForm(_ selector: Package.Target) -> ReferenceKey? {
            guard selector.kind == .objectID || selector.kind == .specificReference else {
                return nil
            }
            return resolveForm(FormID(selector.value))
        }

        /// The spell of the first word of the shout a selector names.
        public func shoutSpell(for selector: Package.Target?) -> ReferenceKey? {
            selector.flatMap(selectedForm).flatMap(shoutSpell(of:))
        }

        /// The spell of the shout's first word; nil when the shouts are not loaded.
        public func shoutSpell(of key: ReferenceKey) -> ReferenceKey? {
            guard
                let shouts = game.aiRecords?.shoutStore,
                let shout = shouts.shouts.values
                    .first(where: { ReferenceKey(resolved: $0.id) == key }),
                let spell = shout.words.first?.spell
            else { return nil }
            return ReferenceKey(resolved: spell.id)
        }

        /// The nearest resident reference within `reach` of `point` that passes `matches`.
        /// One pass, not a sort: a package start asks this once per target. A tie keeps
        /// the first in key order.
        public func nearest(
            to point: SIMD3<Float>, within reach: Float,
            where matches: (RuntimeReferenceEntry) -> Bool
        ) -> ReferenceKey? {
            var best: (key: ReferenceKey, distance: Float)?
            for (entry, distance) in residentPlacedUnsorted(near: point, within: reach)
                where distance < (best?.distance ?? .infinity) && matches(entry)
            {
                best = (entry.key, distance)
            }
            return best?.key
        }

        /// Resident references within `reach` of `point`, nearest first.
        public func residentPlaced(
            near point: SIMD3<Float>, within reach: Float
        ) -> [(entry: RuntimeReferenceEntry, distance: Float)] {
            residentPlacedUnsorted(near: point, within: reach).sorted { $0.distance < $1.distance }
        }

        /// Resident references within `reach` of `point`, in key order.
        func residentPlacedUnsorted(
            near point: SIMD3<Float>, within reach: Float
        ) -> [(entry: RuntimeReferenceEntry, distance: Float)] {
            let entries = game.streamer.residentReferenceIndex().sortedEntries()
            return entries.compactMap { entry in
                let position = entry.placedReference?.placement.position
                    ?? entry.placedActor?.placement.position
                return position.map { (entry: entry, distance: simd_distance($0, point)) }
            }
            .filter { $0.distance <= reach }
        }

        public func setDoorsLocked(
            _ locked: Bool, around center: SIMD3<Float>, radius: Float, owner actor: ReferenceKey
        ) -> PackageActionResult {
            guard let bridge = game.scripts.bridge else { return .failed }
            let base = game.streamer.referenceEntry(key: actor)?.placedActor?.base
            let reach = radius > 0 ? radius : AIPackageActsAdapter.doorReach
            for (entry, _) in residentPlaced(near: center, within: reach) {
                guard
                    let door = entry.placedReference, door.teleportDestination != nil,
                    let lock = bridge.lockState(for: entry.key), lock.isLocked != locked,
                    let owner = door.owner, owns(owner, actor: actor, base: base)
                else { continue }
                var state = lock
                state.isLocked = locked
                _ = bridge.write(state.erased, for: entry.key)
            }
            return .done
        }

        /// A door is the actor's when its base, or a faction the actor is in, owns it.
        private func owns(_ owner: FormID, actor: ReferenceKey, base: FormID?) -> Bool {
            if owner == base {
                return true
            }
            guard
                let bridge = game.scripts.bridge,
                let faction = bridge.referenceKey(forFormID: owner)
            else { return false }
            return bridge.isInFaction(actor, faction: faction) == true
        }

        public func find(
            _ selector: Package.Target, around center: SIMD3<Float>, radius: Float
        ) -> [ReferenceKey] {
            let reach = radius > 0 ? radius : AIPackageActsAdapter.findReach
            let candidates = residentPlaced(near: center, within: reach).map(\.entry)
            switch selector.kind {
            case .specificReference:
                let wanted = game.scripts.bridge?.formIDResolver
                    .flatMap { ReferenceKey.resolve(FormID(selector.value), using: $0) }
                return candidates.map(\.key).filter { $0 == wanted }
            case .objectID:
                return candidates.filter {
                    ConditionFunctions.baseForm(of: $0) == FormID(selector.value)
                }.map(\.key)
            case .objectType:
                guard let type = PackageObjectType(rawValue: selector.value) else { return [] }
                return candidates.filter { matches($0, type) }.map(\.key)
            default:
                return []
            }
        }

        private func matches(_ entry: RuntimeReferenceEntry, _ type: PackageObjectType) -> Bool {
            let base = ConditionFunctions.baseForm(of: entry).rawValue
            let items = game.inventory.runtime?.inventory.baselines.items
            switch type {
            case .weapon:
                return items?.weapons[base] != nil
            case .food:
                return items?.ingestibles[base]?.flags.contains(.food) == true
            case .furniture, .bed, .chair:
                let seats = game.streamer.residentInteraction(reference: entry.formID)?
                    .seats ?? []
                let wanted: UInt16? = type == .bed ? NIFFurnitureMarker.sleepAnimation
                    : type == .chair ? NIFFurnitureMarker.sitAnimation : nil
                return seats.contains { wanted == nil || $0.animationType == wanted }
            }
        }
    }
}
