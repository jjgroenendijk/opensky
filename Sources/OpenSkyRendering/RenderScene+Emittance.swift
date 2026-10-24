// The regions whose weather colours light this scene's external-emittance shapes.

import OpenSkyRenderCore

nonisolated extension RenderScene {
    public var emittanceRegions: Set<UInt32> {
        let instances = (opaque + alphaTested).flatMap(\.instances)
        var regions = Set(instances.compactMap(\.emittance?.region))
        regions.formUnion(particles.compactMap(\.emittance?.region))
        return regions
    }
}
