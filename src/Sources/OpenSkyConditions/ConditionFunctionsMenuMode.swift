// 36 `MenuMode` and 358 `IsPlayerMovingIntoNewSpace`, from xEdit wbDefinitionsTES5.pas.
// `MenuMode` parameter 0 asks about any menu; OpenSky knows no code for one menu type.
// The player moves into a new space while a loading screen shows (Creation Kit wiki).
// See docs/engine/condition-functions-world.md#interface-and-player.

import Foundation
import OpenSkyFormatsESM

/// Whether a menu or a loading screen is open, as the app saw it this frame.
nonisolated public struct MenuConditionResolution: ConditionResolution, Equatable {
    /// Nil in a context with no interface, so the functions fail honestly.
    public var isMenuOpen: Bool?
    public var isLoading: Bool?

    public static let empty = MenuConditionResolution()

    public init(isMenuOpen: Bool? = nil, isLoading: Bool? = nil) {
        self.isMenuOpen = isMenuOpen
        self.isLoading = isLoading
    }
}

nonisolated extension ConditionContext {
    public var menus: MenuConditionResolution {
        get { self[resolution: MenuConditionResolution.self] }
        set { self[resolution: MenuConditionResolution.self] = newValue }
    }
}

nonisolated extension ConditionFunctions {
    static func installMenuMode(_ registry: inout ConditionFunctionRegistry) {
        registry.register(ConditionFunction(
            index: 36, name: "MenuMode", parameter1: .integer
        ) { call in
            guard call.parameter1?.rawValue == 0 else { return .failure(.unresolvedParameter(36)) }
            guard let isOpen = call.context.menus.isMenuOpen else {
                return .failure(.unavailableData(.menu))
            }
            return .success(isTrue(isOpen))
        })
        registry.register(ConditionFunction(
            index: 358, name: "IsPlayerMovingIntoNewSpace"
        ) { call in
            guard let isLoading = call.context.menus.isLoading else {
                return .failure(.unavailableData(.menu))
            }
            return .success(isTrue(isLoading))
        })
    }
}
