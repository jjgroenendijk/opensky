public import OpenSkyMenusInterface

/// What the world adapters use of `SystemMenuModel`.
public protocol SystemMenuModelPort {
    var page: SystemMenuPage { get }
}
