// The world side of the non-combat procedure acts. Object type codes are read from
// the vanilla templates' selectors: docs/engine/package-schedules.md, "Procedure machines".

import OpenSkyConditions
import OpenSkyDialogue
import OpenSkyDialogueInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

extension AIWorldAdapter {
    /// `PTDA` object type codes the vanilla templates use, and the test for each.
    enum PackageObjectType: UInt32 {
        case furniture = 10
        case weapon = 11
        case food = 15
        case bed = 26
        case chair = 27
    }

    func setDoorsLocked(
        _ locked: Bool, around center: SIMD3<Float>, radius: Float, owner actor: ReferenceKey
    ) -> PackageActionResult {
        guard let bridge = game.scripts.bridge else { return .failed }
        let base = game.streamer?.referenceEntry(key: actor)?.placedActor?.base
        let reach = radius > 0 ? radius : Self.doorReach
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

    func find(
        _ selector: Package.Target, around center: SIMD3<Float>, radius: Float
    ) -> [ReferenceKey] {
        let reach = radius > 0 ? radius : Self.findReach
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
            let seats = game.streamer?.residentInteraction(reference: entry.formID)?.seats ?? []
            let wanted: UInt16? = type == .bed ? 2 : type == .chair ? 1 : nil
            return seats.contains { wanted == nil || $0.animationType == wanted }
        }
    }

    func activate(_ target: ReferenceKey, by actor: ReferenceKey) -> PackageActionResult {
        guard let bridge = game.scripts.bridge else { return .failed }
        _ = bridge.activate(target, by: actor, togglesOpen: true)
        return .done
    }

    /// The item moves into the actor's inventory and leaves the world.
    func pickUp(_ item: ReferenceKey, by actor: ReferenceKey) -> PackageActionResult {
        guard
            let bridge = game.scripts.bridge,
            let entry = game.streamer?.referenceEntry(key: item),
            let reference = entry.placedReference,
            game.inventory.scriptAddItem(
                reference.base, count: max(1, reference.itemCount ?? 1), to: actor
            )
        else { return .failed }
        _ = bridge.write(ReferenceDeletionState.deleted.erased, for: item)
        return .done
    }

    /// One line of the topic, chosen as a scene chooses it, voiced and subtitled.
    func say(
        _ topic: FormID?, speaker: ReferenceKey, to target: ReferenceKey?
    ) -> PackageActionResult {
        guard
            let topic, let runtime = game.dialogue.runtime,
            let offer = runtime.topics(linked: [topic], speaker: speaker).offers.first,
            (try? runtime.choose(offer.info, speaker: speaker)) != nil,
            let info = runtime.dialogue.info(offer.info)
        else { return .failed }
        let seconds = game.storyWorld.lineDuration(of: info, speaker: speaker) ?? 3
        game.storyWorld.speak(
            info: offer.info, speaker: speaker, lookAt: target, seconds: seconds
        )
        return .lasts(seconds: seconds)
    }

    /// The conversation opens with the actor's greeting. The package's own topic is not
    /// forced: the greeting is picked as when the player talks to the actor.
    func greet(_ actor: ReferenceKey) -> PackageActionResult {
        game.dialogueMenu.begin(with: actor)
        return game.dialogueMenu.isOpen ? .done : .failed
    }

    /// DialogueActivate: OpenSky has no conversations between two NPCs, so the actor
    /// turns its head to the target.
    func look(at target: ReferenceKey, from actor: ReferenceKey) -> PackageActionResult {
        game.headTracking.setLookTarget(target, for: actor, seconds: 3)
        return .lasts(seconds: 3)
    }
}
