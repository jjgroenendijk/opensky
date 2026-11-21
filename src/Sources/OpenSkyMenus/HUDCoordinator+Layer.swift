// The menu layer passes down a stack: a message box over a menu gives the layer
// back to that menu's movie, and the last menu to close leaves it empty. The HUD
// draws on its own layer under it the whole time.

import Foundation
import OpenSkyFormatsCore
public import OpenSkyMenusInterface
import OpenSkyRendering

struct WeakLayerHolder {
    weak var holder: (any MenuLayerHolder)?
}

extension HUDCoordinator {
    public func takeLayer(for holder: any MenuLayerHolder) {
        layerHolders.removeAll { $0.holder == nil || $0.holder === holder }
        layerHolders.append(WeakLayerHolder(holder: holder))
    }

    /// A holder below the top lets go without a change on screen.
    public func release(by holder: any MenuLayerHolder) {
        let wasOnTop = layerHolders.last?.holder === holder
        layerHolders.removeAll { $0.holder == nil || $0.holder === holder }
        guard wasOnTop else { return }
        if let below = layerHolders.last?.holder {
            below.reclaimLayer()
        } else {
            attempt { try renderer?.setSWFMovie(nil) }
        }
    }
}
