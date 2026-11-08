import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
public import OpenSkyCrime
import OpenSkyCrimeInterface
import OpenSkyDialogue
import OpenSkyFactions
public import OpenSkyFactionsInterface
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMenus
import OpenSkyPerception
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyScripting
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// Witnesses that forward to the narrow parts of `CrimeWorldAdapter`.
extension CrimeWorldAdapter {
    public var hasFactionData: Bool {
        factions.hasFactionData
    }

    public func factionMemberships(of key: ReferenceKey) -> ActorFactionState? {
        factions.factionMemberships(of: key)
    }

    public func socialProfile(of key: ReferenceKey) -> ActorSocialProfile? {
        factions.socialProfile(of: key)
    }

    public func reactionTerms(of observer: ActorSocialProfile) -> ReactionTermsReadout? {
        factions.reactionTerms(of: observer)
    }

    public func joinFaction(_ faction: ReferenceKey, actor key: ReferenceKey, rank: Int8) -> Bool {
        factions.joinFaction(faction, actor: key, rank: rank)
    }

    public func leaveFaction(_ faction: ReferenceKey, actor key: ReferenceKey) -> Bool {
        factions.leaveFaction(faction, actor: key)
    }

    public var gameSeconds: Double? {
        jail.gameSeconds
    }

    public var hourOfDay: Float? {
        jail.hourOfDay
    }

    public func passGameTime(days: Int) {
        jail.passGameTime(days: days)
    }

    public var playerFeet: SIMD3<Float>? {
        jail.playerFeet
    }

    public func enterJail(through marker: ReferenceKey) -> Bool {
        jail.enterJail(through: marker)
    }

    public func leaveJail(to marker: ReferenceKey) -> Bool {
        jail.leaveJail(to: marker)
    }

    public func wearJailOutfit(_ outfit: FormID) -> [FormID] {
        jail.wearJailOutfit(outfit)
    }

    public func loseJailProgress(days: Int, maximumDays: Int) -> Int {
        jail.loseJailProgress(days: days, maximumDays: maximumDays)
    }

    public var lockpickItem: FormID? {
        jail.lockpickItem
    }

    public func movePlayer(toMarker marker: ReferenceKey) -> Bool {
        jail.movePlayer(toMarker: marker)
    }

    public func actorsDetectingPlayer() -> [CrimeObserver] {
        actors.actorsDetectingPlayer()
    }

    public func livingActors() -> [CrimeObserver] {
        actors.livingActors()
    }

    public func isDead(_ key: ReferenceKey) -> Bool {
        actors.isDead(key)
    }

    public func moveActor(_ key: ReferenceKey, to point: SIMD3<Float>) -> String? {
        actors.moveActor(key, to: point)
    }

    public func stopActor(_ key: ReferenceKey) {
        actors.stopActor(key)
    }

    public func suspendPackage(for key: ReferenceKey) {
        actors.suspendPackage(for: key)
    }

    public func resumePackage(for key: ReferenceKey) {
        actors.resumePackage(for: key)
    }

    public var isDialogueOpen: Bool {
        actors.isDialogueOpen
    }

    public var lastDialogueOutcome: String? {
        actors.lastDialogueOutcome
    }

    public func beginDialogue(with speaker: ReferenceKey) {
        actors.beginDialogue(with: speaker)
    }
}
