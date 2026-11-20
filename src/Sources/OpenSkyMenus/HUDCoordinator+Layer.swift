// The one SWF layer passes down a stack: a message box over a menu gives the layer
// back to that menu's movie, and only the last menu to close gives it to the HUD.

import Foundation
public import OpenSkyMenusInterface

struct WeakLayerHolder {
    weak var holder: (any MenuLayerHolder)?
}

extension HUDCoordinator {
    public func suspend(for holder: any MenuLayerHolder) {
        layerHolders.removeAll { $0.holder == nil || $0.holder === holder }
        layerHolders.append(WeakLayerHolder(holder: holder))
        suspend()
    }

    /// A holder below the top lets go without a change on screen.
    public func release(by holder: any MenuLayerHolder) {
        let wasOnTop = layerHolders.last?.holder === holder
        layerHolders.removeAll { $0.holder == nil || $0.holder === holder }
        guard wasOnTop else { return }
        if let below = layerHolders.last?.holder {
            below.reclaimLayer()
        } else {
            start()
        }
    }
}
