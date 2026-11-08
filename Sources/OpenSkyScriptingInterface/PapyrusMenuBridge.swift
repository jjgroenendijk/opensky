public import OpenSkyFormatsESM
import OpenSkyWorldState

/// What the menu natives reach. The app answers it.
@MainActor
public protocol PapyrusMenuBridge: AnyObject {
    func showRaceMenu(limited: Bool)
    /// True when the trip started; a refusal shows its message and returns false.
    func fastTravel(to marker: ReferenceKey) -> Bool
    func setFastTravelEnabled(_ enabled: Bool)
    /// Puts the HUD into or out of the cart ride's mode, which hides it.
    func setHUDCartMode(_ enabled: Bool)
    /// False while a script has fast travel switched off with `EnableFastTravel(false)`.
    var isFastTravelEnabled: Bool { get }
    /// The marker is on the map and the player may travel to it.
    func canFastTravel(to marker: ReferenceKey) -> Bool
    func addToMap(_ marker: ReferenceKey, allowFastTravel: Bool)
    func isMapMarkerVisible(_ marker: ReferenceKey) -> Bool
    /// The player's chosen race for the player, else the actor's record race.
    func race(of actor: ReferenceKey) -> FormID?
    /// Changes the actor's race; nil restores its original race. False when it cannot.
    @discardableResult
    func setRace(of actor: ReferenceKey, to race: FormID?) -> Bool
    /// 0 male, 1 female, or nil for an unknown base.
    func sex(ofBase base: FormID) -> Int?
    /// The race after `useTraits` inheritance.
    func race(ofBase base: FormID) -> FormID?
    /// The base record's own `ACBS` flags, or nil for an unknown base.
    func recordFlags(ofBase base: FormID) -> ActorBase.Flags?
    /// The shouts the base's `SPLO` list gives, in record order.
    func recordShouts(ofBase base: FormID) -> [ReferenceKey]
    /// The base the leveled list chose for this placed actor.
    func leveledBase(of actor: ReferenceKey, base: FormID) -> FormID?
    /// The `VTCK` voice type after template inheritance.
    func voiceType(ofBase base: FormID) -> FormID?
    /// The base record's own `GNAM` gift filter form list.
    func giftFilter(ofBase base: FormID) -> FormID?
    func name(of form: FormID) -> String?
    /// Moves the player next to `target`, loading its cell when it is not loaded.
    func movePlayer(to target: ReferenceKey)
    /// Opens the container menu on the actor's inventory, as a follower's trade does.
    func openInventory(of actor: ReferenceKey)
    func showTrainingMenu(trainer: ReferenceKey)
    /// `filter` holds the form list's entries; nil shows every item.
    func showGiftMenu(
        actor: ReferenceKey, giving: Bool, filter: [ReferenceKey?]?, showsStolenItems: Bool
    )
}
