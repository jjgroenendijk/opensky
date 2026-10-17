// Menu input routes by the menu on top of the stack. Each menu registers its
// own route, so a new menu adds an entry instead of editing a central switch.

import Foundation

public final class MenuRouteTable {
    public typealias Route = (MenuInputEvent) -> Void

    private var routes: [MenuIdentifier: Route] = [:]
    /// Receives every event no menu registered for, such as the system menu's.
    private let fallback: Route

    public init(fallback: @escaping Route) {
        self.fallback = fallback
    }

    public var identifiers: Set<MenuIdentifier> {
        Set(routes.keys)
    }

    /// One route per menu; a second registration is a wiring bug and traps.
    public func register(_ identifiers: MenuIdentifier..., route: @escaping Route) {
        for identifier in identifiers {
            precondition(
                routes[identifier] == nil,
                "menu route \(identifier.name) registered twice"
            )
            routes[identifier] = route
        }
    }

    public func route(_ event: MenuInputEvent, top: MenuIdentifier?) {
        (top.flatMap { routes[$0] } ?? fallback)(event)
    }
}
