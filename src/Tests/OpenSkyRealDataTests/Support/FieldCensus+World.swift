// Census probes for world records: cells, worldspaces, placed objects, and weather.

import Foundation
@testable import OpenSkyFormatsESM

extension FieldCensus {
    mutating func countModel(_ model: ModelData?) {
        count("model", model, [("alternateTextures", { $0.alternateTextures })])
        count("model texture", model?.alternateTextures ?? [], [
            ("shapeName", { $0.shapeName }), ("textureSet", { $0.textureSet }),
            ("shapeIndex", { $0.shapeIndex })
        ])
    }

    mutating func countItem(_ fields: InventoryItemFields) {
        count("item model", fields, [
            ("modelTextureHashes", { $0.modelTextureHashes }),
            ("modelAlternateTextures", { $0.modelAlternateTextures })
        ])
    }

    mutating func countDestructible(_ owner: String, _ destructible: Destructible?) {
        count("\(owner) DEST", destructible, [
            ("health", { $0.health }), ("isVATSTargetable", { $0.isVATSTargetable }),
            ("unknown", { $0.unknown })
        ])
        count("\(owner) DEST stage", destructible?.stages ?? [], [
            ("healthPercent", { $0.healthPercent }), ("index", { $0.index }),
            ("modelDamageStage", { $0.modelDamageStage }), ("flags", { $0.flags }),
            ("selfDamagePerSecond", { $0.selfDamagePerSecond }), ("debris", { $0.debris }),
            ("debrisCount", { $0.debrisCount })
        ])
    }

    mutating func countCell(_ cell: Cell) {
        let extras = cell.extras
        count("CELL", extras, [
            ("waterNoiseTexture", { $0.waterNoiseTexture }),
            ("waterEnvironmentMap", { $0.waterEnvironmentMap }),
            ("waterVelocityCount", { $0.waterVelocityCount }),
            ("maxHeightData", { $0.maxHeightData }), ("legacyFlags", { $0.legacyFlags })
        ])
        count("CELL water velocity", extras.waterVelocities, [("unknown", { $0.unknown })])
        tally("CELL", cell.skipped)
    }

    mutating func countWorldspace(_ worldspace: Worldspace) {
        let details = worldspace.details
        count("WRLD", details, Self.worldspaceDetails)
        count("WRLD map", details.map, [
            ("usableDimensions", { $0.usableDimensions }), ("southEastCell", { $0.southEastCell }),
            ("cameraMinHeight", { $0.cameraMinHeight }), ("cameraMaxHeight", { $0.cameraMaxHeight })
        ])
        count("WRLD map offset", details.mapOffset, [("offset", { $0.offset })])
        count("WRLD large reference", details.largeReferences.flatMap(\.references), [
            ("reference", { $0.reference })
        ])
        countModel(details.cloudModel)
        tally("WRLD", worldspace.skipped)
    }

    mutating func countModelBase(_ base: ModelBase) {
        let details = base.details
        let owner = "\(base.recordType)"
        count(owner, details, [
            ("bounds", { $0.bounds }), ("destructible", { $0.destructible }),
            ("waterType", { $0.waterType }), ("associatedSpell", { $0.associatedSpell }),
            ("randomTeleports", { $0.randomTeleports })
        ])
        count("\(owner) entry points", details.markerEntryPoints, [
            ("entryPoints", { $0.entryPoints })
        ])
        count("\(owner) tree", details.treeData, Self.treeData)
        countModel(details.model)
        countDestructible(owner, details.destructible)
        tally(owner, base.skipped)
    }

    mutating func countWeather(_ weather: Weather) {
        let sky = weather.sky
        count("WTHR", sky, [
            ("maxCloudLayers", { $0.maxCloudLayers }), ("skyStatics", { $0.skyStatics }),
            ("moonGlare", { $0.moonGlare }), ("auroraModel", { $0.auroraModel }),
            ("legacyCloudTextures", { $0.legacyCloudTextures }),
            ("legacyCloudSpeeds", { $0.legacyCloudSpeeds })
        ])
        count("WTHR cloud", sky.cloudLayers, [
            ("index", { $0.index }), ("colors", { $0.colors })
        ])
        count("WTHR cloud color", sky.cloudLayers.compactMap(\.colors), [
            ("sunrise", { $0.sunrise }), ("sunset", { $0.sunset })
        ])
        count("WTHR sound", sky.sounds, [("sound", { $0.sound }), ("type", { $0.type })])
        countModel(sky.auroraModel)
        tally("WTHR", weather.skipped)
    }

    mutating func countProjectile(_ placed: PlacedProjectile) {
        count("\(placed.recordType)", placed, [
            ("formID", { $0.formID }), ("editorID", { $0.editorID }),
            ("isInitiallyDisabled", { $0.isInitiallyDisabled }), ("owner", { $0.owner }),
            ("linkedReferences", { $0.linkedReferences }), ("scriptData", { $0.scriptData.scripts })
        ])
        tally("\(placed.recordType)", placed.skipped)
    }

    static var treeData: [Probe<ModelBaseDetails.TreeData>] {
        [
            ("trunkFlexibility", { $0.trunkFlexibility }),
            ("branchFlexibility", { $0.branchFlexibility }),
            ("trunkAmplitude", { $0.trunkAmplitude }), ("frontAmplitude", { $0.frontAmplitude }),
            ("backAmplitude", { $0.backAmplitude }), ("sideAmplitude", { $0.sideAmplitude }),
            ("frontFrequency", { $0.frontFrequency }), ("backFrequency", { $0.backFrequency }),
            ("sideFrequency", { $0.sideFrequency }), ("leafFlexibility", { $0.leafFlexibility }),
            ("leafAmplitude", { $0.leafAmplitude })
        ]
    }

    static var worldspaceDetails: [Probe<WorldspaceDetails>] {
        [
            ("maxHeightData", { $0.maxHeightData }), ("fixedCenter", { $0.fixedCenter }),
            ("interiorLighting", { $0.interiorLighting }), ("location", { $0.location }),
            ("lodWater", { $0.lodWater }), ("lodWaterHeight", { $0.lodWaterHeight }),
            ("mapImage", { $0.mapImage }), ("cloudModel", { $0.cloudModel }),
            ("distantLODMultiplier", { $0.distantLODMultiplier }), ("boundsMin", { $0.boundsMin }),
            ("canopyShadow", { $0.canopyShadow }), ("waterNoiseTexture", { $0.waterNoiseTexture }),
            ("waterEnvironmentMap", { $0.waterEnvironmentMap }),
            ("hdLODDiffuseTexture", { $0.hdLODDiffuseTexture }),
            ("hdLODNormalTexture", { $0.hdLODNormalTexture }), ("offsets", { $0.offsets })
        ]
    }
}
