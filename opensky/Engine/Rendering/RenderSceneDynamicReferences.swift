// Per-reference draw-list extraction for exterior dynamic-body handoff
// (issue #401). Kept beside RenderScene.swift as its streaming satellite.

nonisolated extension RenderScene {
    /// The ordinary scene with selected simulated references removed. Their
    /// instances are handed to the occupied cell separately, while terrain,
    /// lighting, animation, and every untagged placement stay cell-owned.
    func excludingDynamicReferences(_ references: Set<UInt32>) -> RenderScene {
        replacingDrawGroups(
            opaque: Self.filter(opaque) { !references.contains($0.referenceFormID) },
            alphaTested: Self.filter(alphaTested) {
                !references.contains($0.referenceFormID)
            },
            keepsAncillaryContent: true
        )
    }

    /// Only one simulated reference's draw instances, with no cell-wide
    /// terrain or environment content. This is the unit of draw handoff across
    /// an exterior boundary.
    func dynamicReferenceScene(_ reference: UInt32) -> RenderScene {
        replacingDrawGroups(
            opaque: Self.filter(opaque) { $0.referenceFormID == reference },
            alphaTested: Self.filter(alphaTested) { $0.referenceFormID == reference },
            keepsAncillaryContent: false
        )
    }

    private static func filter(
        _ groups: [DrawGroup],
        keeping predicate: (DrawInstance) -> Bool
    ) -> [DrawGroup] {
        groups.compactMap { group in
            let instances = group.instances.filter(predicate)
            guard !instances.isEmpty else { return nil }
            return DrawGroup(mesh: group.mesh, material: group.material, instances: instances)
        }
    }

    private func replacingDrawGroups(
        opaque: [DrawGroup],
        alphaTested: [DrawGroup],
        keepsAncillaryContent: Bool
    ) -> RenderScene {
        RenderScene(
            opaque: opaque,
            alphaTested: alphaTested,
            terrain: keepsAncillaryContent ? terrain : [],
            water: keepsAncillaryContent ? water : [],
            sky: keepsAncillaryContent ? sky : nil,
            lighting: keepsAncillaryContent ? lighting : nil,
            pointLights: keepsAncillaryContent ? pointLights : [],
            grass: keepsAncillaryContent ? grass : [],
            particles: keepsAncillaryContent ? particles : [],
            animations: keepsAncillaryContent ? animations : []
        )
    }

    private init(
        opaque: [DrawGroup],
        alphaTested: [DrawGroup],
        terrain: [TerrainDrawItem],
        water: [WaterDrawItem],
        sky: SkyParameters?,
        lighting: RenderLighting?,
        pointLights: [RenderPointLight],
        grass: [GrassDrawGroup],
        particles: [ParticlePlayback],
        animations: [any RenderAnimation]
    ) {
        self.opaque = opaque
        self.alphaTested = alphaTested
        self.terrain = terrain
        self.water = water
        self.sky = sky
        self.lighting = lighting
        self.pointLights = pointLights
        self.grass = grass
        self.particles = particles
        self.animations = animations
    }
}
