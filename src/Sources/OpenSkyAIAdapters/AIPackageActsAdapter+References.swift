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

        /// The procedures ignore the radius: they reach every door of the interior the
        /// owner stands in at the place, and none outdoors
        /// (docs/engine/crime.md#owners-lock-and-unlock).
        public func setDoorsLocked(
            _ locked: Bool, around center: SIMD3<Float>, radius _: Float, owner actor: ReferenceKey
        ) -> PackageActionResult {
            guard game.scripts.bridge != nil else { return .failed }
            guard let place = game.streamer.cellLocation(of: actor), case .interior = place else {
                return .done
            }
            let doors = residentPlacedUnsorted(near: center, within: .infinity).map(\.entry)
                .filter { game.streamer.cellLocation(of: $0.key) == place }
            setLocked(locked, doors: doors, owner: actor)
            return .done
        }

        /// The package door flags reach the owner's doors within 5000 units: in an interior
        /// only its own cell, outdoors every loaded cell.
        func unlockOwnedDoors(of actor: ReferenceKey) -> PackageActionResult {
            guard
                let place = game.streamer.cellLocation(of: actor),
                let center = packageMoves.packageActorPosition(actor)
            else { return .failed }
            var doors = residentPlacedUnsorted(
                near: center, within: AIPackageActsAdapter.ownerDoorReach
            ).map(\.entry)
            if case .interior = place {
                doors = doors.filter { game.streamer.cellLocation(of: $0.key) == place }
            }
            setLocked(false, doors: doors, owner: actor)
            return .done
        }

        /// Locks or unlocks each door the actor owns that has lock data, and the door
        /// behind a load door with it.
        private func setLocked(
            _ locked: Bool, doors: [RuntimeReferenceEntry], owner actor: ReferenceKey
        ) {
            guard game.scripts.bridge != nil else { return }
            let base = game.streamer.referenceEntry(key: actor)?.placedActor?.base
            for entry in doors {
                guard let owned = ownedDoor(entry, actor: actor, base: base) else { continue }
                if writeLock(locked, keys: owned.keys), owned.isLoadDoor {
                    markOpened(!locked, cellsOf: owned.keys)
                }
            }
        }

        /// The door and the door behind it when the actor owns them, and whether it is
        /// a load door. A door without an owner takes the linked door's.
        private func ownedDoor(
            _ entry: RuntimeReferenceEntry, actor: ReferenceKey, base: FormID?
        ) -> (keys: [ReferenceKey], isLoadDoor: Bool)? {
            guard let door = entry.placedReference, isDoor(entry) else { return nil }
            let isLoadDoor = door.teleportDestination != nil
            let partner = door.teleportDestination.flatMap {
                game.streamer.referenceEntry(formID: $0.door)
            }
            guard
                let owner = door.owner ?? partner?.placedReference?.owner,
                owns(owner, actor: actor, base: base, isLoadDoor: isLoadDoor)
            else { return nil }
            return ([entry.key, partner?.key].compactMap(\.self), isLoadDoor)
        }

        /// Writes the lock state of each key that has lock data; true when one had.
        private func writeLock(_ locked: Bool, keys: [ReferenceKey]) -> Bool {
            guard let bridge = game.scripts.bridge else { return false }
            var changed = false
            for key in keys {
                guard var state = bridge.lockState(for: key) else { continue }
                changed = true
                if state.isLocked != locked {
                    state.isLocked = locked
                    _ = bridge.write(state.erased, for: key)
                }
            }
            return changed
        }

        private func isDoor(_ entry: RuntimeReferenceEntry) -> Bool {
            entry.placedReference?.teleportDestination != nil
                || game.streamer.residentInteraction(reference: entry.formID)?.action == .open
        }

        /// An owner's lock or unlock closes or opens the interiors on both sides to the
        /// player (docs/engine/crime.md#opened-by-the-owner).
        private func markOpened(_ opened: Bool, cellsOf doors: [ReferenceKey]) {
            guard let bridge = game.scripts.bridge else { return }
            for door in doors {
                guard
                    case let .interior(cell)? = game.streamer.cellLocation(of: door),
                    let key = bridge.referenceKey(forFormID: cell)
                else { continue }
                bridge.updateScriptedState(of: key) {
                    $0.setFlag(ScriptedStateName.openedByOwner, opened ? true : nil)
                }
            }
        }

        /// A door is the actor's when its base owns it, or, for a load door only, a
        /// faction the actor is in.
        private func owns(
            _ owner: FormID, actor: ReferenceKey, base: FormID?, isLoadDoor: Bool
        ) -> Bool {
            if owner == base {
                return true
            }
            guard
                isLoadDoor,
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

extension AIPackageActsAdapter {
    func packageReference(
        _ target: Package.Target, actor: ReferenceKey, aliasQuest: FormID?
    ) -> ReferenceKey? {
        references.packageReference(target, actor: actor, aliasQuest: aliasQuest)
    }
}
