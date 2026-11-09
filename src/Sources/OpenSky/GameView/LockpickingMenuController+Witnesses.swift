import Foundation
import OpenSkyCells
import OpenSkyCrime
import OpenSkyFormatsESM
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface

/// Witnesses that forward to the narrow parts of `LockpickingMenuController`.
extension LockpickingMenuController {
    func tick() {
        board.tick()
    }
}
