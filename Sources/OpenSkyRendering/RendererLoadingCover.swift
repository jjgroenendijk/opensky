// The loading screen's 3D object. While a cover is set, the scene pass draws
// only the `.loadingCover` layer and the screen-space layers, so the world
// behind it never shows. See docs/engine/loading-screens.md.

import Metal

extension Renderer {
    /// Shows `placements` in place of the world, or the world again for nil.
    /// An empty list is a dark screen with only the overlay.
    public func setLoadingCover(_ placements: [RenderPlacement]?) throws {
        let next = placements.map { RenderScene(instances: $0) }
        let retiring = effects.loadingCover?.residencyAllocations ?? []
        effects.loadingCover = next
        if let next {
            try growRings(
                drawCount: scene.drawCount + rigDrawCount + effects.scene.drawCount,
                instanceCount: scene.instanceCount + rigInstanceCount + effects.scene.instanceCount
            )
            let added = next.residencyAllocations
            if !added.isEmpty {
                residencySet.addAllocations(added)
                residencySet.commit()
            }
        }
        retireAllocations(retiring)
    }
}
