// The world side of the inventory domain: what `InventoryCoordinator` reads
// from the running session. The app answers it; a test passes a fake.
// See docs/engine/coordinators.md.

import OpenSkyFormatsESM
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `InventoryCoordinator` reads from the running world. Reference lookups
/// go through the item runtime's `references` instead.
@MainActor
public protocol InventoryWorld: AnyObject {
    /// The interaction under the crosshair, which every item action acts on.
    var crosshairInteraction: PlacedInteraction? { get }
    /// A step in front of the camera, in the player's cell. Nil when no cell
    /// is resident, because an object needs a cell to exist in.
    func dropPlacement() -> DropPlacement?
    /// The resident ACHR nearest the camera.
    func nearestActorEntry() -> RuntimeReferenceEntry?
    /// Every resident container interaction, for merchant nomination.
    func containerInteractions() -> [PlacedInteraction]
    /// What the actor's cell build could not draw, tagged by its ACHR FormID.
    func appearanceSkipReasons(forActor reference: FormID) -> [String]
    /// The bounty taking one `item` from `reference` would accrue. Zero
    /// without a crime runtime.
    func theftBounty(of item: FormID, from reference: ReferenceKey) -> Int32
    /// Brings magic in line after an equip change on `holder`: readied spells
    /// leave the hands it now fills, and worn enchantments are re-read.
    func equipmentChanged(on holder: InventoryHolder)
    /// The enchantment `item` carries, as worn by `owner`.
    func enchantmentLine(of item: FormID, on owner: ReferenceKey) -> String?
    var enchantmentCacheReadout: EnchantmentCacheReadout { get }
    /// Game days passed, which harvest regrowth counts in. Nil without a clock.
    var gameDaysPassed: Float? { get }
    /// Republishes the crosshair target, so a changed prompt label shows at once.
    func refreshInteractionTarget()
}

/// One container-menu transaction, named by its direction.
nonisolated public enum ContainerTransfer: Equatable, Sendable {
    /// Container to player, marked as theft when the container is owned.
    case take
    /// Player to container.
    case store
    /// Merchant to player, for gold.
    case buy
    /// Player to merchant, for gold.
    case sell
}
