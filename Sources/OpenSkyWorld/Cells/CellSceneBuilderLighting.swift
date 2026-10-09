// Interior lighting: CELL XCLL over LTMP -> LGTM, and LIGH/XEMI placements as
// point lights. Exterior scenes keep sun and sky lighting.

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyRendering
import simd

nonisolated public struct InteriorLightingBuild: Sendable {
    public let lighting: RenderLighting
    public let pointLights: [RenderPointLight]
}

nonisolated extension CellSceneBuilder {
    nonisolated public func buildInteriorLighting(
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
    nonisolated public static func resolvedLighting(
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

    nonisolated public func resolvePointLights(
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

    nonisolated public func lightingTemplateIndexBuildingIfNeeded() -> [UInt32: LightingTemplate] {
        if let lightingTemplateIndex {
            return lightingTemplateIndex
        }
        let index = loadOrderRecords(of: "LGTM") { record, _ in
            try LightingTemplate(record: record)
        }
        lightingTemplateIndex = index
        return index
    }

    nonisolated public func lightIndexBuildingIfNeeded() -> [UInt32: LightRecord] {
        if let lightIndex {
            return lightIndex
        }
        let index = loadOrderRecords(of: "LIGH") { record, _ in try LightRecord(record: record) }
        lightIndex = index
        return index
    }
}
