// App side of `CrimeCoordinator`: builds it from the provider, attaches the
// perception pass as its witnesses, and answers `CrimeSessionWorld` from the
// session systems. The rules live in the coordinator (docs/engine/coordinators.md).

import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCrime
import OpenSkyCrimeInterface
import OpenSkyDialogue
import OpenSkyFactions
import OpenSkyFactionsInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
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
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `CrimeWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
protocol CrimeWorldHost: AnyObject {
    var actorWorld: ActorWorldAdapter { get }
    var dialogue: DialogueCoordinator { get }
    var dialogueMenu: DialogueMenuController { get }
    var dialogueWorld: DialogueWorldAdapter { get }
    var storyWorld: StoryWorldAdapter { get }
    var factions: FactionCoordinator { get }
    var hud: HUDCoordinator { get }
    var inventory: InventoryCoordinator { get }
    var inventoryWorld: InventoryWorldAdapter { get }
    var progression: ProgressionCoordinator { get }
    var mapWorld: MapWorldAdapter { get }
    var packages: PackageCoordinator { get }
    var perception: PerceptionCoordinator { get }
    var renderer: Renderer? { get }
    var gameSession: GameSession? { get }
    var scripts: ScriptCoordinator { get }
    var streamer: CellStreamer? { get }
    var worldState: WorldStateStore { get }
}

/// Answers `CrimeSessionWorld` from the session systems `game` owns.
final class CrimeWorldAdapter {
    unowned let game: any CrimeWorldHost

    init(game: any CrimeWorldHost) {
        self.game = game
    }

    /// Perception is built first: its pass answers "did anybody see it" for every crime.
    func witnesses() -> PerceptionCrimeWitnesses {
        let store = game.worldState
        return PerceptionCrimeWitnesses(
            perception: game.perception.runtime,
            isAlive: { [weak store] key in
                store?.component(ActorDeathState.self, for: key)?.isDead != true
            }
        )
    }

    /// Ownership reads the same FACT store as the hostility derivation.
    func sessionData(_ provider: WorldDataStores) -> CrimeSessionData? {
        guard
            let factionStore = provider.factionStore,
            let pluginName = provider.magicItemPluginName
        else { return nil }
        return CrimeSessionData(
            runtime: CrimeRuntime(
                store: game.worldState, factions: factionStore,
                settings: CrimeSettings.resolve(store: provider.gameSettings)
            ),
            locations: provider.locationStore,
            pluginName: pluginName,
            texts: CrimeTexts
                .resolve(store: provider.gameSettings) { [game] in game.mapWorld.text($0) }
        )
    }

    func run(_ commands: [CrimeCommand]) {
        for command in commands {
            switch command {
            case let .showNotice(text): game.hud.showNotification(text)
            case let .applyGuardHostility(hostility): game.factions.setCrimeHostility(hostility)
            case let .incrementStat(name, amount): game.worldState.incrementMiscStat(
                    name,
                    by: amount
                )
            case let .stoleFromFaction(faction, value, witnessed):
                game.scripts.bridge?.noteStolenValue(value, from: faction, witnessed: witnessed)
            case let .settlePickpocketCatches(faction, forgotten):
                game.inventoryWorld.settlePickpocketCatches(
                    chargedTo: faction,
                    forgotten: forgotten
                )
            case let .speakTrespassWarning(witness):
                game.storyWorld.sayTopic("TRES", speaker: witness, lookAt: .player)
            case let .raiseStat(name, value):
                let current = game.worldState.miscStats.value(name)
                if value > current {
                    game.worldState.incrementMiscStat(name, by: value - current)
                }
            }
        }
    }
}

extension CrimeWorldAdapter: CrimeSessionWorld {
    // MARK: - Places and references

    var references: (any PapyrusWorldReferenceSource)? {
        game.streamer
    }

    var currentCellLocation: CellSceneLocation? {
        game.streamer?.currentCellLocation
    }

    func cellOwnership(at location: CellSceneLocation) -> RecordOwnership? {
        game.streamer?.residentScene(at: location)?.owner
    }

    func cellTrespassFlags(at location: CellSceneLocation) -> CellTrespassFlags {
        game.streamer?.residentScene(at: location)?.trespass ?? CellTrespassFlags()
    }

    func cellLocationLink(at location: CellSceneLocation) -> (link: FormID, plugin: String)? {
        guard
            let scene = game.streamer?.residentScene(at: location),
            let link = scene.locationLink,
            let plugin = scene.ownerPluginName
        else { return nil }
        return (link, plugin)
    }

    func itemValue(of item: FormID) -> Int64 {
        Int64(game.inventory.runtime?.inventory.baselines.items.gameValue(of: item) ?? 0)
    }

    func actorName(_ key: ReferenceKey) -> String {
        game.dialogueWorld.speakerLabel(for: key)
    }

    var crosshairInteraction: PlacedInteraction? {
        game.hud.interactionTarget?.interaction
    }

    // MARK: - Factions

    var hasFactionData: Bool {
        game.factions.runtime != nil
    }

    func factionMemberships(of key: ReferenceKey) -> ActorFactionState? {
        game.factions.memberships(of: key)
    }

    func socialProfile(of key: ReferenceKey) -> ActorSocialProfile? {
        game.factions.profile(of: key)
    }

    /// The same derivation the combat loop asks.
    func reactionTerms(of observer: ActorSocialProfile) -> ReactionTermsReadout? {
        guard
            let player = game.factions.profile(of: .player),
            let derivation = game.factions.runtime?.derivation
        else { return nil }
        return ReactionTermsReadout(
            decision: derivation.decide(observer, toward: player),
            hostilityOverride: observer.hostilityOverride,
            crime: derivation.crime.crimeReaction(of: observer, toward: player),
            relationship: derivation.relationshipReaction(of: observer, toward: player),
            scriptedRank: derivation.scriptedRank(of: observer, toward: player),
            faction: derivation.factionReaction(of: observer, toward: player)
        )
    }

    func joinFaction(_ faction: ReferenceKey, actor key: ReferenceKey, rank: Int8) -> Bool {
        game.factions.join(faction, actor: key, rank: rank)
    }

    func leaveFaction(_ faction: ReferenceKey, actor key: ReferenceKey) -> Bool {
        game.factions.leave(faction, actor: key)
    }

    // MARK: - Items and vendors

    var inventory: (any InventoryAccess)? {
        game.inventory.runtime?.inventory
    }

    func targetOwnership() -> ReferenceOwnershipReadout? {
        game.inventory.targetOwnership()
    }

    func stolenPlayerStacks() -> [ItemStackReadout] {
        guard let runtime = game.inventory.runtime else { return [] }
        return game.inventory.readout(
            runtime.inventory.inventory(of: runtime.player).stacks.filter(\.stolen)
        )
    }

    func vendor(faction key: ReferenceKey) -> Vendor? {
        game.inventory.vendors?.core.vendor(faction: key)
    }

    func vendor(of actor: ReferenceKey) -> Vendor? {
        game.inventory.vendors?.vendor(of: actor)
    }

    // MARK: - Clock and player

    var gameSeconds: Double? {
        game.gameSession?.gameClock.totalGameSeconds
    }

    var hourOfDay: Float? {
        game.gameSession?.gameClock.hourOfDay
    }

    func passGameTime(days: Int) {
        guard let gameSession = game.gameSession else { return }
        gameSession.gameClock = GameClock(
            totalGameSeconds: gameSession.gameClock.totalGameSeconds
                + Double(days) * GameClock.secondsPerDay
        )
    }

    var playerFeet: SIMD3<Float>? {
        game.gameSession?.locomotion.status.feetPosition
    }

    func enterJail(through marker: ReferenceKey) -> Bool {
        guard
            let streamer = game.streamer,
            let door = streamer.pluginPlacement(of: marker)?.entry
            ?? streamer.referenceEntry(key: marker),
            door.placedReference?.teleportDestination != nil
        else { return false }
        return streamer.requestDoorTransition(from: door.formID)
    }

    /// The cell's PrisonMarker is the `XTEL` target of the outside one.
    func leaveJail(to marker: ReferenceKey) -> Bool {
        guard
            let streamer = game.streamer,
            let outside = streamer.pluginPlacement(of: marker)?.entry,
            let inside = outside.placedReference?.teleportDestination?.door
        else { return false }
        return streamer.requestDoorTransition(from: inside)
    }

    func wearJailOutfit(_ outfit: FormID) -> [FormID] {
        guard
            let inventory = game.inventory.runtime?.inventory,
            let pieces = inventory.baselines.outfitStacks(
                outfit, roll: inventory.roll(of: .player)
            ),
            game.inventoryWorld.setOutfit(outfit, on: .player)
        else { return [] }
        return pieces.map(\.item)
    }

    func loseJailProgress(days: Int, maximumDays: Int) -> Int {
        game.progression.loseJailProgress(days: days, maximumDays: maximumDays).count
    }

    var lockpickItem: FormID? {
        game.inventory.locks.lockpickItem
    }

    func movePlayer(toMarker marker: ReferenceKey) -> Bool {
        guard
            let renderer = game.renderer, let gameSession = game.gameSession,
            let placement = game.streamer?.referenceEntry(key: marker)?.placedReference?.placement
        else { return false }
        let camera = SceneCamera.teleport(placement: placement)
        renderer.camera = camera
        gameSession.reseedMovement(camera: camera)
        return true
    }

    // MARK: - Guards

    func actorsDetectingPlayer() -> [CrimeObserver] {
        guard let perception = game.perception.runtime else { return [] }
        let detecting = Set(perception.observersDetecting(.player))
        return game.actorWorld.combatActors()
            .filter { !$0.isDead && detecting.contains($0.key) }
            .map { CrimeObserver(key: $0.key, feet: $0.feet) }
    }

    func livingActors() -> [CrimeObserver] {
        game.actorWorld.combatActors()
            .filter { !$0.isDead }
            .map { CrimeObserver(key: $0.key, feet: $0.feet) }
    }

    func isDead(_ key: ReferenceKey) -> Bool {
        game.worldState.component(ActorDeathState.self, for: key)?.isDead == true
    }

    func moveActor(_ key: ReferenceKey, to point: SIMD3<Float>) -> String? {
        game.streamer.map { "\($0.moveActor(key, to: point))" }
    }

    func stopActor(_ key: ReferenceKey) {
        _ = game.streamer?.stopActor(key)
    }

    func suspendPackage(for key: ReferenceKey) {
        game.packages.suspend(key)
    }

    func resumePackage(for key: ReferenceKey) {
        game.packages.resume(key)
    }

    var isDialogueOpen: Bool {
        game.dialogueMenu.isOpen
    }

    var lastDialogueOutcome: String? {
        game.dialogue.lastOutcome
    }

    func beginDialogue(with speaker: ReferenceKey) {
        game.dialogueMenu.begin(with: speaker)
    }
}
