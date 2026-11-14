// The regions whose weather colours light this scene's external-emittance shapes.

import OpenSkyRenderCore

nonisolated extension RenderScene {
    public var emittanceRegions: Set<UInt32> {
        var regions = Set<UInt32>()
        for list in [opaque, alphaTested] {
            for group in list {
                for instance in group.instances {
                    if let region = instance.emittance?.region {
                        regions.insert(region)
                    }
                }
            }
        }
        for particle in particles {
            if let region = particle.emittance?.region {
                regions.insert(region)
            }
        }
        return regions
    }
}
