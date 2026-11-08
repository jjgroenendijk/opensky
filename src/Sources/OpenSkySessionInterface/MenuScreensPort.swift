public import OpenSkyMenusInterface

/// What the world adapters use of `MenuScreens`.
public protocol MenuScreensPort: AnyObject {
    func tick(now: Double)
    var book: any BookMenuPort { get }
    var gift: any GiftMenuPort { get }
    var magic: any MagicMenuPort { get }
    var pointerRoutes: [MenuIdentifier: (MenuPointerEvent) -> Void] { get }
    var sleepWait: any SleepWaitMenuPort { get }
    var training: any TrainingMenuPort { get }
    var crafting: any CraftingMenuPort { get }
    var keyRoutes: [MenuIdentifier: (MenuInputEvent) -> Void] { get }
}
