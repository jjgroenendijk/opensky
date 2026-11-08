// Applies the shadow map size from `ShadowSettings`: a new size builds a new
// cascade array and retires the old one once the frames that use it finish.

import Metal
import OpenSkyFormatsCore
import OpenSkyRenderCore

extension Renderer {
    /// Keeps the old map when the device cannot make a new one.
    func resizeShadowMapIfNeeded() {
        let size = shadowSettings.resolution
        guard
            shadow.map.width != size,
            let map = attempt({ try Self.makeShadowMap(device: device, resolution: size) })
        else { return }
        retireAllocations([shadow.map])
        residencySet.addAllocation(map)
        residencySet.commit()
        shadow.map = map
    }
}
