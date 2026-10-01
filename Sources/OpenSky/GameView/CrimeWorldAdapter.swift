// App side of `CrimeCoordinator`: builds it from the provider, attaches the
// perception pass as its witnesses, and answers `CrimeSessionWorld` from the
// session systems. The rules live in the coordinator (docs/engine/coordinators.md).

import OpenSkyActorsInterface
import OpenSkyCombat
import OpenSkyCrime
import OpenSkyCrimeInterface
import OpenSkyDialogue
import OpenSkyFactions
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyPerception
import OpenSkyRendering
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// Answers `CrimeSessionWorld` from the session systems `game` owns.
final class CrimeWorldAdapter {
    unowned let game: GameViewController

    init(game: GameViewController) {
        self.game = game
    }

    /// After `wireFactions` and `wireWorldItems`: it reads the same FACT store
    /// as the hostility derivation and joins the take path.
    func wireCrime(provider: any WorldDataProviding) {
        guard
            let factionStore = (provider as? FactionDataProviding)?.factionStore,
            let pluginName = (provider as? MagicDataProviding)?.magicItemPluginName
        else { return }
        game.crime.attach(world: self)
        game.crime.wire(
            runtime: CrimeRuntime(store: game.worldState, factions: factionStore),
            locations: (provider as? LocationDataProviding)?.locationStore,
            pluginName: pluginName
        )
        game.inventory.runtime?.crime = game.crime.reporter
    }

    /// A witnessed crime is one the perception pass actually saw.
    func attachWitnesses(perception: PerceptionRuntime?) {
        let store = game.worldState
        game.crime.attachWitnesses(PerceptionCrimeWitnesses(
            perception: perception,
            isAlive: { [weak store] key in
                store?.component(ActorDeathState.self, for: key)?.isDead != true
            }
        ))
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

    func cellLocationLink(at location: CellSceneLocation) -> (link: FormID, plugin: String)? {
        guard
            let scene = game.streamer?.residentScene(at: location),
            let link = scene.locationLink,
            let plugin = scene.ownerPluginName
        else { return nil }
        return (link, plugin)
    }

    func itemValue(of item: FormID) -> Int64 {
        Int64(game.inventory.runtime?.inventory.baselines.items.definition(item)?.value ?? 0)
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

    func applyGuardHostility(_ hostility: GuardCrimeHostility) {
        game.factions.setCrimeHostility(hostility)
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

    func openBarter(with actor: ReferenceKey, vendorFaction: ReferenceKey?) -> String {
        game.containerMenu.openBarter(with: actor, vendorFaction: vendorFaction)
    }

    // MARK: - Clock and player

    var gameSeconds: Double? {
        game.renderer?.gameClock.totalGameSeconds
    }

    var hourOfDay: Float? {
        game.renderer?.gameClock.hourOfDay
    }

    func passGameTime(days: Int) {
        guard let renderer = game.renderer else { return }
        renderer.gameClock = GameClock(
            totalGameSeconds: renderer.gameClock.totalGameSeconds
                + Double(days) * GameClock.secondsPerDay
        )
    }

    var playerFeet: SIMD3<Float>? {
        game.renderer?.locomotion.status.feetPosition
    }

    func movePlayer(toMarker marker: ReferenceKey) -> Bool {
        guard
            let renderer = game.renderer,
            let placement = game.streamer?.referenceEntry(key: marker)?.placedReference?.placement
        else { return false }
        let camera = SceneCamera.teleport(placement: placement)
        renderer.camera = camera
        renderer.reseedMovement(camera: camera)
        return true
    }

    // MARK: - Guards

    func actorsDetectingPlayer() -> [CrimeObserver] {
        guard let perception = game.perception.runtime else { return [] }
        let detecting = Set(perception.observersDetecting(.player))
        return game.combatActors()
            .filter { !$0.isDead && detecting.contains($0.key) }
            .map { CrimeObserver(key: $0.key, feet: $0.feet) }
    }

    func moveActor(_ key: ReferenceKey, to point: SIMD3<Float>) -> String? {
        game.streamer.map { "\($0.moveActor(key, to: point))" }
    }

    func stopActor(_ key: ReferenceKey) {
        _ = game.streamer?.stopActor(key)
    }

    func suspendPackage(for key: ReferenceKey) {
        game.packages.runtime?.setSuspended(true, actor: key)
    }

    func resumePackage(for key: ReferenceKey) {
        game.resumePackage(for: key)
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
