public import OpenSkyMenusInterface

/// What the world adapters use of `CraftingMenuCoordinator`.
public protocol CraftingMenuPort: AnyObject {
    @discardableResult func open() -> Bool
    /// The tab title, the rows of the shown tab, and the selected row.
    var readout: MenuTextPanel { get }
    /// What the last action did, such as the slider's uses.
    var lastResult: String { get }
    /// Whether the menu's movie loaded, and why it did not.
    var movieState: MenuMovieState { get }
    /// What the bottom bar's skill bar was given, such as "Enchanting 15, 40%".
    var skillBar: String? { get }
}
