// The world side of the inventory domain: what `InventoryCoordinator` reads
// from the running session. The app answers it; a test passes a fake. Changes
// to the world go back to the app as `InventoryCommand` values.
// See docs/engine/coordinators.md.

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyProgressionInterface
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
    /// What the actor's cell build could not draw, tagged by its ACHR FormID.
    func appearanceSkipReasons(forActor reference: FormID) -> [String]
    /// The bounty taking one `item` from `reference` would accrue. Zero
    /// without a crime runtime.
    func theftBounty(of item: FormID, from reference: ReferenceKey) -> Int32
    /// The enchantment `item` carries, as worn by `owner`.
    func enchantmentLine(of item: FormID, on owner: ReferenceKey) -> String?
    var enchantmentCacheReadout: EnchantmentCacheReadout { get }
    /// Game days passed, which a harvest records. Nil without a clock.
    var gameDaysPassed: Float? { get }
    /// The Tamriel month, 1 to 12, which picks a harvest's season. Nil without a clock.
    var gameMonth: Int? { get }
    /// The player's current Speech skill. Nil without actor values.
    func playerSpeechSkill() -> Float?
    /// `key`'s current Pickpocket skill. Nil without actor values.
    func pickpocketSkill(of key: ReferenceKey) -> Float?
    /// `key`'s current `CarryWeight`. Nil without actor values.
    func carryWeight(of key: ReferenceKey) -> Float?
    /// Whether `observer` has detected the player right now.
    func detectsPlayer(_ observer: ReferenceKey) -> Bool
    /// Lands the poison `poison` on `target`, from the player. False when nothing landed.
    func applyPlacedPoison(_ poison: FormID, on target: ReferenceKey) -> Bool
    /// `effect`'s name in the load order's language.
    func magicEffectName(_ effect: ResolvedMagicEffect) -> String
    /// The text a passing Set Activate Label perk of the player puts on `reference`'s
    /// prompt, such as a werewolf's "Feed". Nil keeps the authored label.
    func perkActivateLabel(for reference: FormID) -> String?
    /// Whether `base` is a `BOOK`, which the crosshair offers to read.
    func isBook(_ base: FormID) -> Bool
    var isPlayerSneaking: Bool { get }
    /// What `key`'s perks make of `value`, with `subjects` bound and `seams` laid over
    /// the live conditions.
    func perkModified(
        _ value: Float,
        at entryPoint: PerkEntryPoint,
        on key: ReferenceKey,
        subjects: PerkEvaluationSubjects,
        seams: ConditionContext
    ) -> Float
}

extension InventoryWorld {
    public func pickpocketSkill(of _: ReferenceKey) -> Float? {
        nil
    }

    public func carryWeight(of _: ReferenceKey) -> Float? {
        nil
    }

    public func detectsPlayer(_: ReferenceKey) -> Bool {
        false
    }

    public func applyPlacedPoison(_: FormID, on _: ReferenceKey) -> Bool {
        false
    }

    public var gameMonth: Int? {
        nil
    }

    public func magicEffectName(_ effect: ResolvedMagicEffect) -> String {
        effect.displayName
    }

    /// A session with no actor values trades at the starting Speech skill.
    public func playerSpeechSkill() -> Float? {
        nil
    }

    public func perkActivateLabel(for _: FormID) -> String? {
        nil
    }

    public func isBook(_: FormID) -> Bool {
        false
    }

    public var isPlayerSneaking: Bool {
        false
    }

    /// A session with no perks leaves every value as it is.
    public func perkModified(
        _ value: Float,
        at _: PerkEntryPoint,
        on _: ReferenceKey,
        subjects _: PerkEvaluationSubjects,
        seams _: ConditionContext
    ) -> Float {
        value
    }
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
