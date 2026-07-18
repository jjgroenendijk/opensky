// Interior lighting assembly: resolve CELL XCLL against LTMP -> LGTM,
// turn supported LIGH/XEMI placements into point lights. Exterior scenes
// deliberately keep sun/sky lighting unchanged for milestone 3.7.

import simd

nonisolated struct InteriorLightingBuild {
    let lighting: RenderLighting
    let pointLights: [RenderPointLight]
}

extension CellSceneBuilder {
    nonisolated func buildInteriorLighting(
        cell: Cell,
        references: [PlacedReference]
    ) -> InteriorLightingBuild? {
        guard cell.isInterior else { return nil }
        let template = cell.lightingTemplate.flatMap {
            lightingTemplateIndexBuildingIfNeeded()[$0.rawValue]?.values
        }
        guard let values = Self.resolvedLighting(cell: cell.lighting, template: template) else {
            return nil
        }
        let ambient = values.directionalAmbient ?? .black
        let azimuth = MatrixMath.radians(fromDegrees: Float(values.directionalRotationXY))
        let elevation = MatrixMath.radians(fromDegrees: Float(values.directionalRotationZ))
        let direction = simd_normalize(SIMD3<Float>(
            cosf(elevation) * cosf(azimuth),
            cosf(elevation) * sinf(azimuth),
            sinf(elevation)
        ))
        let fog: FogParameters? = if values.fogFar > values.fogNear, values.fogFar > 0 {
            FogParameters(
                nearColor: values.fogNearColor,
                farColor: values.fogFarColor ?? values.fogNearColor,
                nearDistance: max(0, values.fogNear),
                farDistance: values.fogFar,
                power: max(0.01, values.fogPower),
                maximum: min(max(values.fogMax ?? 1, 0), 1)
            )
        } else {
            nil
        }
        let lighting = RenderLighting(
            ambientColor: values.ambientColor,
            directionalAmbient: ambient,
            directionalDirection: direction,
            directionalColor: values.directionalColor * max(0, values.directionalFade),
            fog: fog
        )
        return InteriorLightingBuild(
            lighting: lighting,
            pointLights: resolvePointLights(references)
        )
    }

    /// Per-field source selection. An inherited field prefers LGTM; a
    /// cell-local field prefers XCLL. Missing optional tails fall back to
    /// whichever source exists instead of manufacturing values.
    nonisolated static func resolvedLighting(
        cell: CellLightingValues?,
        template: CellLightingValues?
    ) -> CellLightingValues? {
        guard let cell else { return template }
        guard let template else { return cell }
        let flags = cell.inherits
        func choose<T>(_ flag: CellLightingValues.InheritFlags, _ local: T, _ base: T) -> T {
            flags.contains(flag) ? base : local
        }
        func chooseOptional<T>(
            _ flag: CellLightingValues.InheritFlags,
            _ local: T?,
            _ base: T?
        ) -> T? {
            flags.contains(flag) ? (base ?? local) : (local ?? base)
        }
        return CellLightingValues(
            ambientColor: choose(.ambientColor, cell.ambientColor, template.ambientColor),
            directionalColor: choose(
                .directionalColor, cell.directionalColor, template.directionalColor
            ),
            fogNearColor: choose(.fogColor, cell.fogNearColor, template.fogNearColor),
            fogNear: choose(.fogNear, cell.fogNear, template.fogNear),
            fogFar: choose(.fogFar, cell.fogFar, template.fogFar),
            directionalRotationXY: choose(
                .directionalRotation,
                cell.directionalRotationXY,
                template.directionalRotationXY
            ),
            directionalRotationZ: choose(
                .directionalRotation,
                cell.directionalRotationZ,
                template.directionalRotationZ
            ),
            directionalFade: choose(
                .directionalFade, cell.directionalFade, template.directionalFade
            ),
            fogClipDistance: choose(
                .fogClipDistance, cell.fogClipDistance, template.fogClipDistance
            ),
            fogPower: choose(.fogPower, cell.fogPower, template.fogPower),
            directionalAmbient: chooseOptional(
                .ambientColor, cell.directionalAmbient, template.directionalAmbient
            ),
            fogFarColor: chooseOptional(.fogColor, cell.fogFarColor, template.fogFarColor),
            fogMax: chooseOptional(.fogMax, cell.fogMax, template.fogMax),
            lightFadeBegin: chooseOptional(
                .lightFadeDistances, cell.lightFadeBegin, template.lightFadeBegin
            ),
            lightFadeEnd: chooseOptional(
                .lightFadeDistances, cell.lightFadeEnd, template.lightFadeEnd
            ),
            inherits: []
        )
    }

    nonisolated func resolvePointLights(
        _ references: [PlacedReference]
    ) -> [RenderPointLight] {
        let lights = lightIndexBuildingIfNeeded()
        return references.compactMap { reference in
            let base = lights[reference.base.rawValue]
            let emitted = reference.emittance.flatMap { lights[$0.rawValue] }
            guard let light = emitted ?? base, light.isSupportedPointLight else { return nil }
            let radius = reference.lightRadius ?? Float(light.radius)
            guard radius.isFinite, radius > 0 else { return nil }
            return RenderPointLight(
                position: reference.placement.position,
                radius: radius,
                color: light.color * max(0, light.fade),
                falloffExponent: max(0.01, light.falloffExponent)
            )
        }
    }

    nonisolated func lightingTemplateIndexBuildingIfNeeded() -> [UInt32: LightingTemplate] {
        if let lightingTemplateIndex {
            return lightingTemplateIndex
        }
        var index: [UInt32: LightingTemplate] = [:]
        if let top = file.topGroup(of: "LGTM"), let children = try? top.children() {
            for case let .record(record) in children where record.type == "LGTM" {
                if let template = try? LightingTemplate(record: record) {
                    index[record.formID] = template
                }
            }
        }
        lightingTemplateIndex = index
        return index
    }

    nonisolated func lightIndexBuildingIfNeeded() -> [UInt32: LightRecord] {
        if let lightIndex {
            return lightIndex
        }
        var index: [UInt32: LightRecord] = [:]
        if let top = file.topGroup(of: "LIGH"), let children = try? top.children() {
            for case let .record(record) in children where record.type == "LIGH" {
                if let light = try? LightRecord(record: record) {
                    index[record.formID] = light
                }
            }
        }
        lightIndex = index
        return index
    }
}
