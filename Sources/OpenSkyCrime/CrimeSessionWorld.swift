// The world side of the crime domain: what `CrimeCoordinator` reads from and
// asks of the running session. The app answers it; a test passes a fake.
// See docs/engine/coordinators.md.

import OpenSkyCrimeInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyWorldInterface
import simd

/// What `CrimeCoordinator` reads from and asks of the running world.
@MainActor
public protocol CrimeSessionWorld: AnyObject {
    // MARK: - Places and references

    /// Nil without a streamed world.
    var references: (any PapyrusWorldReferenceSource)? { get }
    var currentCellLocation: CellSceneLocation? { get }
    /// The `XOWN` of a resident cell.
    func cellOwnership(at location: CellSceneLocation) -> RecordOwnership?
    /// The `XLCN` of a resident cell, with the plugin that placed the cell.
    func cellLocationLink(at location: CellSceneLocation) -> (link: FormID, plugin: String)?
    /// Zero for a form no loaded plugin describes.
    func itemValue(of item: FormID) -> Int64
    func actorName(_ key: ReferenceKey) -> String
    var crosshairInteraction: PlacedInteraction? { get }

    // MARK: - Factions

    /// False without faction data.
    var hasFactionData: Bool { get }
    /// Seeded first. Nil without faction data.
    func factionMemberships(of key: ReferenceKey) -> ActorFactionState?
    /// Seeded first. Nil without faction data or for an actor not resident.
    func socialProfile(of key: ReferenceKey) -> ActorSocialProfile?
    /// Every term of what `observer` makes of the player.
    func reactionTerms(of observer: ActorSocialProfile) -> ReactionTermsReadout?
    func applyGuardHostility(_ hostility: GuardCrimeHostility)
    /// - Returns: true when the stored memberships changed.
    func joinFaction(_ faction: ReferenceKey, actor key: ReferenceKey, rank: Int8) -> Bool
    /// - Returns: true when the actor was a member.
    func leaveFaction(_ faction: ReferenceKey, actor key: ReferenceKey) -> Bool

    // MARK: - Items and vendors

    /// Nil without an item runtime.
    var inventory: (any InventoryAccess)? { get }
    func targetOwnership() -> ReferenceOwnershipReadout?
    func stolenPlayerStacks() -> [ItemStackReadout]
    func vendor(faction key: ReferenceKey) -> Vendor?
    func vendor(of actor: ReferenceKey) -> Vendor?
    func openBarter(with actor: ReferenceKey, vendorFaction: ReferenceKey?) -> String

    // MARK: - Clock and player

    /// `GameClock.totalGameSeconds`. Nil when no world is running.
    var gameSeconds: Double? { get }
    var hourOfDay: Float? { get }
    func passGameTime(days: Int)
    var playerFeet: SIMD3<Float>? { get }
    /// Puts the player on a resident marker. False when it is not resident.
    func movePlayer(toMarker marker: ReferenceKey) -> Bool

    // MARK: - Guards

    /// Every living resident actor that detects the player. Empty without a
    /// perception pass.
    func actorsDetectingPlayer() -> [CrimeObserver]
    /// Nil without a streamed world.
    func moveActor(_ key: ReferenceKey, to point: SIMD3<Float>) -> String?
    func stopActor(_ key: ReferenceKey)
    func suspendPackage(for key: ReferenceKey)
    func resumePackage(for key: ReferenceKey)
    var isDialogueOpen: Bool { get }
    var lastDialogueOutcome: String? { get }
    func beginDialogue(with speaker: ReferenceKey)
}

/// One actor that sees the player, and where it stands.
nonisolated public struct CrimeObserver: Equatable, Sendable {
    public let key: ReferenceKey
    public let feet: SIMD3<Float>

    public init(key: ReferenceKey, feet: SIMD3<Float>) {
        self.key = key
        self.feet = feet
    }
}
