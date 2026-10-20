// A `CrimeSessionWorld` made of plain values, for `CrimeCoordinatorTests`.

@testable import OpenSkyCrime
@testable import OpenSkyCrimeInterface
@testable import OpenSkyFactionsInterface
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyInventoryInterface
@testable import OpenSkyWorldInterface
@testable import OpenSkyWorldState
import simd

@MainActor
final class FakeCrimeSessionWorld: CrimeSessionWorld {
    var references: (any PapyrusWorldReferenceSource)?
    var currentCellLocation: CellSceneLocation?
    var cellOwners: [CellSceneLocation: RecordOwnership] = [:]
    var cellLinks: [CellSceneLocation: FormID] = [:]
    var crosshairInteraction: PlacedInteraction?
    var hasFactionData = true
    var memberships: [ReferenceKey: ActorFactionState] = [:]
    var profiles: [ReferenceKey: ActorSocialProfile] = [:]
    var inventory: (any InventoryAccess)?
    var gameSeconds: Double?
    var hourOfDay: Float?
    var playerFeet: SIMD3<Float>?
    var observers: [CrimeObserver] = []
    private(set) var moved: [ReferenceKey: SIMD3<Float>] = [:]
    private(set) var stopped: [ReferenceKey] = []
    private(set) var suspended: Set<ReferenceKey> = []
    private(set) var resumed: [ReferenceKey] = []
    var isDialogueOpen = false
    /// What `beginDialogue` sets `isDialogueOpen` to.
    var dialogueOpens = false
    var lastDialogueOutcome: String?
    private(set) var spokenTo: [ReferenceKey] = []
    var trespassFlags: [CellSceneLocation: CellTrespassFlags] = [:]
    var living: [CrimeObserver] = []
    var dead: Set<ReferenceKey> = []
    /// Where `enterJail` puts the player; nil refuses the door.
    var jailCell: CellSceneLocation?
    var lockpick: FormID?
    private(set) var leftJail: [ReferenceKey] = []
    private(set) var lostProgress: [(days: Int, maximum: Int)] = []

    func cellTrespassFlags(at location: CellSceneLocation) -> CellTrespassFlags {
        trespassFlags[location] ?? CellTrespassFlags()
    }

    func livingActors() -> [CrimeObserver] {
        living.filter { !dead.contains($0.key) }
    }

    func isDead(_ key: ReferenceKey) -> Bool {
        dead.contains(key)
    }

    func enterJail(through _: ReferenceKey) -> Bool {
        jailCell != nil
    }

    func leaveJail(to marker: ReferenceKey) -> Bool {
        leftJail.append(marker)
        return true
    }

    func loseJailProgress(days: Int, maximumDays: Int) -> Int {
        lostProgress.append((days, maximumDays))
        return 3
    }

    var lockpickItem: FormID? {
        lockpick
    }

    func cellOwnership(at location: CellSceneLocation) -> RecordOwnership? {
        cellOwners[location]
    }

    func cellLocationLink(at location: CellSceneLocation) -> (link: FormID, plugin: String)? {
        cellLinks[location].map { ($0, CrimeFixture.pluginName) }
    }

    func itemValue(of _: FormID) -> Int64 {
        0
    }

    func actorName(_ key: ReferenceKey) -> String {
        "Actor \(key)"
    }

    func factionMemberships(of key: ReferenceKey) -> ActorFactionState? {
        hasFactionData ? memberships[key] ?? ActorFactionState() : nil
    }

    func socialProfile(of key: ReferenceKey) -> ActorSocialProfile? {
        profiles[key]
    }

    func reactionTerms(of _: ActorSocialProfile) -> ReactionTermsReadout? {
        nil
    }

    func joinFaction(_ faction: ReferenceKey, actor key: ReferenceKey, rank: Int8) -> Bool {
        let state = memberships[key] ?? ActorFactionState()
        memberships[key] = state.joining(faction, rank: rank)
        return memberships[key]?.memberships != state.memberships
    }

    func leaveFaction(_ faction: ReferenceKey, actor key: ReferenceKey) -> Bool {
        let state = memberships[key] ?? ActorFactionState()
        memberships[key] = state.leaving(faction)
        return memberships[key]?.memberships != state.memberships
    }

    func targetOwnership() -> ReferenceOwnershipReadout? {
        nil
    }

    func stolenPlayerStacks() -> [ItemStackReadout] {
        []
    }

    func vendor(faction _: ReferenceKey) -> Vendor? {
        nil
    }

    func vendor(of _: ReferenceKey) -> Vendor? {
        nil
    }

    func openBarter(with _: ReferenceKey, vendorFaction _: ReferenceKey?) -> String {
        "Barter opened."
    }

    func passGameTime(days: Int) {
        gameSeconds = (gameSeconds ?? 0) + Double(days) * 86400
    }

    func movePlayer(toMarker _: ReferenceKey) -> Bool {
        false
    }

    func actorsDetectingPlayer() -> [CrimeObserver] {
        observers
    }

    func moveActor(_ key: ReferenceKey, to point: SIMD3<Float>) -> String? {
        moved[key] = point
        return "moving"
    }

    func stopActor(_ key: ReferenceKey) {
        stopped.append(key)
    }

    func suspendPackage(for key: ReferenceKey) {
        suspended.insert(key)
    }

    func resumePackage(for key: ReferenceKey) {
        resumed.append(key)
    }

    func beginDialogue(with speaker: ReferenceKey) {
        spokenTo.append(speaker)
        isDialogueOpen = dialogueOpens
    }
}

/// Places every reference in one cell and decodes none of them.
final class FakeCrimeReferences: PapyrusWorldReferenceSource {
    let cell: CellSceneLocation

    init(cell: CellSceneLocation) {
        self.cell = cell
    }

    func referenceEntry(formID _: FormID) -> RuntimeReferenceEntry? {
        nil
    }

    func referenceEntry(key _: ReferenceKey) -> RuntimeReferenceEntry? {
        nil
    }

    func cellLocation(of _: ReferenceKey) -> CellSceneLocation? {
        cell
    }

    func activateChildren(of _: ReferenceKey) -> [ActivateChild] {
        []
    }
}
