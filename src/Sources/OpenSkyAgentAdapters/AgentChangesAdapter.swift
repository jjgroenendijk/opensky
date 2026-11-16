// `openskycli game debug` commands that change the world as a script or a console line
// would, and `state music`: each goes through the same Papyrus world bridge the natives
// use. A form is the load-order FormID the reference game's console takes.

import Foundation
import OpenSkyAgentControl
import OpenSkyAudio
import OpenSkyCombatInterface
import OpenSkyEffects
import OpenSkyFormatsESM
import OpenSkyInventoryInterface
import OpenSkyRenderCore
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `AgentChangesAdapter` reads from the session.
@MainActor
public protocol AgentChangesHost: AnyObject, SendableMetatype {
    var actorWorld: any ActorWorldPort { get }
    var audio: any AudioPort { get }
    var combatWorld: any CombatWorldPort { get }
    var effects: any EffectsPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var scripts: any ScriptPort { get }
}

/// Part of `AgentWorldAdapter`, over its own narrow host.
struct AgentChangesAdapter {
    let hub: AgentHub
    let game: any AgentChangesHost
}

extension AgentChangesAdapter {
    func perform(_ change: AgentWorldChange) throws(AgentFailure) -> AgentJSON {
        switch change {
        case let .imageSpaceModifier(request): try applyModifier(request)
        case let .cast(spell, caster, target): try cast(spell, from: caster, at: target)
        case let .spell(spell, reference, known): try setSpell(spell, on: reference, known: known)
        case let .enable(reference, enabled): try setEnabled(reference, enabled: enabled)
        case let .delete(reference): try delete(reference)
        case let .lock(reference, locked): try setLocked(reference, locked: locked)
        case let .activate(reference, activator): try activate(reference, by: activator)
        case let .decal(reference, height): try placeDecal(on: reference, height: height)
        case let .spawn(base, anchor): try spawn(base, at: anchor)
        }
    }

    func musicState() -> AgentJSON {
        guard let music = game.audio.musicDirector?.readout else { return ["music": .null] }
        return [
            "musicType": .string(music.musicType),
            "musicTypeFormID": music.musicTypeFormID.map { .formID($0.rawValue) } ?? .null,
            "state": .string(music.state), "track": .init(music.trackPath),
            "trackIndex": .init(music.trackIndex), "trackCount": .init(music.trackCount),
            "elapsedSeconds": .init(music.elapsedSeconds), "paused": .bool(music.paused),
            "combat": .bool(music.combat), "special": .init(music.interruptedBySpecial),
            "scripted": .array(music.scriptedMusic.map { .formID($0.rawValue) }),
            "enabled": .bool(music.enabled), "refusal": .init(music.refusal)
        ]
    }

    private var bridge: any PapyrusWorldStateBridgePort {
        get throws(AgentFailure) {
            guard let bridge = game.scripts.bridge else { throw hub.notReady() }
            return bridge
        }
    }

    /// A base form or a reference by load-order FormID, loaded or not.
    private func form(_ text: String) throws(AgentFailure) -> ReferenceKey {
        guard let formID = FormID(hexText: text) else {
            throw AgentFailure(.invalidArgument, "'\(text)' is not a hex FormID")
        }
        guard let key = try bridge.referenceKey(forFormID: formID) else {
            throw AgentFailure(.notFound, "no form \(AgentJSON.formID(formID.rawValue))")
        }
        return key
    }

    /// `player`, `target`, or any reference by FormID, loaded or not.
    private func reference(_ text: String) throws(AgentFailure) -> ReferenceKey {
        switch text.lowercased() {
        case "player", "target": try hub.resolveReference(text).key
        default: try form(text)
        }
    }

    private func formJSON(_ key: ReferenceKey) throws(AgentFailure) -> AgentJSON {
        if key == .player {
            return .formID(FormID.playerReference.rawValue)
        }
        return try bridge.localFormID(of: key).map { .formID($0.rawValue) } ?? .null
    }

    private func applyModifier(_ request: AgentModifierRequest) throws(AgentFailure) -> AgentJSON {
        guard let session = game.gameSession else { throw hub.notReady() }
        let key = try form(request.modifier)
        if request.remove {
            game.effects.stopModifier(key, fadeOut: request.fadeSeconds, on: &session.imageSpace)
        } else {
            let started = game.effects.startModifier(
                key, strength: request.strength, looping: request.crossFade,
                fadeIn: request.fadeSeconds, on: &session.imageSpace
            )
            guard started else {
                throw AgentFailure(.notFound, "\(request.modifier) is no image space modifier")
            }
        }
        return ["modifiers": Self.modifiersJSON(session.imageSpace.modifiers)]
    }

    /// Each running modifier, its strength now, and how long it has run.
    static func modifiersJSON(_ modifiers: ImageSpaceModifierRuntime) -> AgentJSON {
        .array(modifiers.instances.map { instance in
            [
                "name": .string(instance.name), "strength": .init(instance.strength),
                "currentStrength": .init(instance.currentStrength),
                "elapsed": .init(instance.elapsed), "held": .bool(instance.looping),
                "fadeIn": .init(instance.fadeIn),
                "remaining": instance.remaining.map { .init($0) } ?? .null
            ]
        })
    }

    private func cast(
        _ spell: String, from caster: String, at target: String?
    ) throws(AgentFailure) -> AgentJSON {
        let spellKey = try form(spell)
        let casterKey = try reference(caster)
        let targetKey = try target
            .map { (text: String) throws(AgentFailure) in try reference(text) }
        let cast = try bridge.castSpell(spellKey, from: casterKey, at: targetKey, blame: nil)
        guard cast else { throw AgentFailure(.failed, "\(spell) could not be cast") }
        return try [
            "cast": .bool(cast), "caster": formJSON(casterKey),
            "target": targetKey.map { (key: ReferenceKey) throws(AgentFailure) in
                try formJSON(key)
            } ?? .null
        ]
    }

    private func setSpell(
        _ spell: String, on actor: String, known: Bool
    ) throws(AgentFailure) -> AgentJSON {
        let spellKey = try form(spell)
        let actorKey = try reference(actor)
        let changed = known
            ? try bridge.addSpell(spellKey, to: actorKey)
            : try bridge.removeSpell(spellKey, from: actorKey)
        return try ["ref": formJSON(actorKey), "changed": .bool(changed), "known": .bool(known)]
    }

    private func setEnabled(_ text: String, enabled: Bool) throws(AgentFailure) -> AgentJSON {
        let key = try reference(text)
        guard key != .player
        else { throw AgentFailure(.invalidArgument, "the player stays enabled") }
        try bridge.write(ReferenceEnableState(isEnabled: enabled).erased, for: key)
        let stored = try bridge.referenceState(for: key)?.enableState.isEnabled ?? enabled
        return try ["ref": formJSON(key), "enabled": .bool(stored)]
    }

    private func delete(_ text: String) throws(AgentFailure) -> AgentJSON {
        let key = try reference(text)
        guard key != .player else { throw AgentFailure(.invalidArgument, "the player stays") }
        try bridge.write(ReferenceDeletionState.deleted.erased, for: key)
        let stored = try bridge.referenceState(for: key)?.deletion.isDeleted ?? true
        return try ["ref": formJSON(key), "deleted": .bool(stored)]
    }

    /// A reference with no lock gets the level a script's `Lock` gives it.
    private func setLocked(_ text: String, locked: Bool) throws(AgentFailure) -> AgentJSON {
        let key = try reference(text)
        var lock = try bridge.lockState(for: key)
            ?? ReferenceLockState(isLocked: false, level: Self.scriptLockLevel, key: nil)
        lock.isLocked = locked
        try bridge.write(lock.erased, for: key)
        return try [
            "ref": formJSON(key), "locked": .bool(locked), "level": .init(Int(lock.level))
        ]
    }

    /// The level `ObjectReference.Lock` gives a reference that has no XLOC.
    private static let scriptLockLevel: UInt8 = 1

    /// A script activation, so it is not an open action, as the native's own call.
    private func activate(
        _ text: String, by activatorText: String
    ) throws(AgentFailure) -> AgentJSON {
        let key = try reference(text)
        let activator = try reference(activatorText)
        let outcome = try bridge.activate(key, by: activator, togglesOpen: false)
        return try [
            "ref": formJSON(key), "by": formJSON(activator),
            "queuedEvents": .init(outcome.queuedEvents),
            "cappedByRecursion": .bool(outcome.cappedByRecursion)
        ]
    }

    /// A one-handed blade's hit on the actor's side that faces the player: its impact
    /// for the actor's race material, struck at the actor, so the decal rides the body.
    private func placeDecal(on text: String, height: Float) throws(AgentFailure) -> AgentJSON {
        let key = try hub.resolveReference(text).key
        guard let actor = game.actorWorld.combatActor(key: key) else {
            throw AgentFailure(.invalidArgument, "\(text) is no loaded actor")
        }
        let material = game.combatWorld.impactMaterial(of: key)
        guard var impact = game.combatWorld.impact(
            dataSetEditorID: Self.bladeImpacts, material: material
        ) else { throw AgentFailure(.failed, "no blade impact for \(text)'s material") }
        impact.target = key
        let player = game.actorWorld.combatActor(key: .player)?.feet ?? actor.feet
        var toward = SIMD2(player.x - actor.feet.x, player.y - actor.feet.y)
        toward = simd_length(toward) > 0 ? simd_normalize(toward) : SIMD2(0, 1)
        let point = actor.feet + SIMD3(toward * Self.bodyRadius, height)
        let before = skinDecalBones(of: key).count
        game.combatWorld.playImpact(impact, at: point)
        let bones = skinDecalBones(of: key)
        return try [
            "ref": formJSON(key), "position": .init(point),
            "placed": .bool(bones.count > before), "skinDecals": .array(bones.map { .string($0) })
        ]
    }

    /// The impact data set a one-handed sword's `INAM` names in Skyrim.esm.
    private static let bladeImpacts = "WPNzBlade1HandImpactSet"

    /// The bone each skin decal on the actor rides, or `feet`.
    private func skinDecalBones(of actor: ReferenceKey) -> [String] {
        let skin = game.effects.skinDecals
        return skin.owners.filter { $0.value == actor }.keys.sorted()
            .map { skin.bones[$0] ?? "feet" }
    }

    /// About the radius of a person's body, so the point lies on the skin, not inside it.
    private static let bodyRadius: Float = 15

    private func spawn(_ base: String, at anchor: String) throws(AgentFailure) -> AgentJSON {
        let baseKey = try form(base)
        let anchorKey = try reference(anchor)
        guard let placed = try bridge.spawnReference(of: baseKey, at: anchorKey) else {
            throw AgentFailure(.failed, "\(base) could not be placed")
        }
        return try ["ref": formJSON(placed), "base": .string(base)]
    }
}
