// The acts of AI procedures that are not walks: door locks, finds, activation,
// pickup, speech, greetings, attacks, casts, and shouts.
// See docs/engine/package-schedules.md, "Procedure machines".

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldState
import simd

extension AIWorldAdapter {
    /// How far LockDoors and UnlockDoors reach when the package place has no radius.
    static let doorReach: Float = 2048
    /// How far a find looks when its place has no radius.
    static let findReach: Float = 2048

    func packageReference(
        _ target: Package.Target, actor: ReferenceKey, aliasQuest: FormID?
    ) -> ReferenceKey? {
        if let key = packageTargetKey(target, aliasQuest: aliasQuest) {
            return key
        }
        switch target.kind {
        case .linkedReference:
            let entry = game.streamer?.referenceEntry(key: actor)
            let links = entry?.placedReference?.linkedReferences
                ?? entry?.placedActor?.details.linkedReferences ?? []
            let keyword = FormID(target.value).nonNull
            return links.first { $0.keyword == keyword }.flatMap { resolveForm($0.ref) }
        case .objectID:
            let position = packageActorPosition(actor) ?? .zero
            return nearest(to: position, within: .infinity) {
                ConditionFunctions.baseForm(of: $0) == FormID(target.value)
            }
        default:
            return nil
        }
    }

    func stopPackageActor(_ actor: ReferenceKey) {
        _ = stopActor(actor)
    }

    func packageAction(_ action: PackageAction, actor: ReferenceKey) -> PackageActionResult {
        switch action {
        case let .setDoorsLocked(locked, center, radius):
            setDoorsLocked(locked, around: center, radius: radius, owner: actor)
        case let .find(selector, center, radius):
            .found(find(selector, around: center, radius: radius))
        case let .activate(target):
            activate(target, by: actor)
        case let .pickUp(item):
            pickUp(item, by: actor)
        case let .say(topic, target):
            say(topic, speaker: actor, to: target)
        case .forceGreet:
            greet(actor)
        case let .talk(target):
            look(at: target, from: actor)
        default:
            combatAction(action, actor: actor)
        }
    }

    private func combatAction(_ action: PackageAction, actor: ReferenceKey) -> PackageActionResult {
        guard let bridge = game.scripts.bridge else { return .failed }
        switch action {
        case let .attack(target?, startsCombat: true):
            return bridge.startActorCombat(actor, target: target) ? .done : .failed
        case let .cast(selector, target):
            guard let spell = selector.flatMap(selectedForm) else { return .failed }
            return bridge.castSpell(spell, from: actor, at: target) ? .done : .failed
        case let .shout(selector, target):
            guard let spell = selector.flatMap(shoutSpell) else { return .failed }
            return bridge.castSpell(spell, from: actor, at: target) ? .done : .failed
        default:
            return .failed
        }
    }

    private func resolveForm(_ formID: FormID) -> ReferenceKey? {
        game.scripts.bridge?.formIDResolver.flatMap { ReferenceKey.resolve(formID, using: $0) }
    }

    /// The form a selector names by its object ID, such as a spell.
    private func selectedForm(_ selector: Package.Target) -> ReferenceKey? {
        guard selector.kind == .objectID || selector.kind == .specificReference else {
            return nil
        }
        return resolveForm(FormID(selector.value))
    }

    /// The spell of the first word of the shout a selector names.
    private func shoutSpell(_ selector: Package.Target) -> ReferenceKey? {
        guard
            let key = selectedForm(selector),
            let shouts = game.worldData?.shoutStore,
            let shout = shouts.shouts.values.first(where: { ReferenceKey(resolved: $0.id) == key }),
            let spell = shout.words.first?.spell
        else { return nil }
        return ReferenceKey(resolved: spell.id)
    }

    /// The nearest resident reference within `reach` of `point` that passes `matches`.
    func nearest(
        to point: SIMD3<Float>, within reach: Float,
        where matches: (RuntimeReferenceEntry) -> Bool
    ) -> ReferenceKey? {
        residentPlaced(near: point, within: reach).first { matches($0.entry) }?.entry.key
    }

    /// Resident references within `reach` of `point`, nearest first.
    func residentPlaced(
        near point: SIMD3<Float>, within reach: Float
    ) -> [(entry: RuntimeReferenceEntry, distance: Float)] {
        let entries = game.streamer?.residentReferenceIndex().sortedEntries() ?? []
        return entries.compactMap { entry in
            let position = entry.placedReference?.placement.position
                ?? entry.placedActor?.placement.position
            return position.map { (entry: entry, distance: simd_distance($0, point)) }
        }
        .filter { $0.distance <= reach }
        .sorted { $0.distance < $1.distance }
    }
}
