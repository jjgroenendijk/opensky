// Base object and CELL FormIDs moved into another FormID space, so a base or a
// cell from a later plugin resolves in the load order (docs/formats/formid.md).

import Foundation

nonisolated extension ModelBase: FormIDRenumbering {
    public func renumbered(_ translate: (FormID) -> FormID) -> ModelBase {
        var copy = self
        copy.formID = translate(formID)
        copy.sounds = sounds.map {
            Sounds(
                activation: $0.activation.renumbered(translate),
                close: $0.close.renumbered(translate),
                loop: $0.loop.renumbered(translate)
            )
        }
        copy.scriptData = scriptData.renumbered(translate)
        copy.keywords = keywords.renumbered(translate)
        copy.interactionKeyword = interactionKeyword.renumbered(translate)
        copy.produce = produce.map {
            HarvestProduce(
                ingredient: $0.ingredient.renumbered(translate),
                harvestSound: $0.harvestSound.renumbered(translate),
                seasonalChance: $0.seasonalChance
            )
        }
        copy.voiceType = voiceType.renumbered(translate)
        copy.details = details.renumbered(translate)
        return copy
    }
}

nonisolated extension StaticObject: FormIDRenumbering {
    public func renumbered(_ translate: (FormID) -> FormID) -> StaticObject {
        var copy = self
        copy.formID = translate(formID)
        copy.model = model?.renumbered(translate)
        copy.directionalMaterial = directionalMaterial.map {
            DirectionalMaterial(
                maxAngle: $0.maxAngle,
                material: $0.material.renumbered(translate),
                consideredSnow: $0.consideredSnow
            )
        }
        return copy
    }
}

nonisolated extension TextureSet: FormIDRenumbering {
    public func renumbered(_ translate: (FormID) -> FormID) -> TextureSet {
        var copy = self
        copy.formID = translate(formID)
        return copy
    }
}

nonisolated extension LightRecord: FormIDRenumbering {
    public func renumbered(_ translate: (FormID) -> FormID) -> LightRecord {
        var copy = self
        copy.formID = translate(formID)
        copy.details.sound = details.sound.renumbered(translate)
        copy.details.lensFlare = details.lensFlare.renumbered(translate)
        return copy
    }
}

nonisolated extension Cell: FormIDRenumbering {
    public func renumbered(_ translate: (FormID) -> FormID) -> Cell {
        var copy = self
        copy.formID = translate(formID)
        copy.waterType = waterType.renumbered(translate)
        copy.lightingTemplate = lightingTemplate.renumbered(translate)
        copy.regions = regions.map(translate)
        copy.acousticSpace = acousticSpace.renumbered(translate)
        copy.musicType = musicType.renumbered(translate)
        copy.location = location.renumbered(translate)
        copy.encounterZone = encounterZone.renumbered(translate)
        copy.owner = owner.renumbered(translate)
        copy.extras.imageSpace = extras.imageSpace.renumbered(translate)
        copy.extras.lockList = extras.lockList.renumbered(translate)
        copy.extras.skyRegion = extras.skyRegion.renumbered(translate)
        return copy
    }
}

nonisolated extension ModelData {
    func renumbered(_ translate: (FormID) -> FormID) -> ModelData {
        var copy = self
        copy.alternateTextures = alternateTextures.map {
            AlternateTexture(
                shapeName: $0.shapeName,
                textureSet: translate($0.textureSet),
                shapeIndex: $0.shapeIndex
            )
        }
        return copy
    }
}

nonisolated extension KeywordList {
    func renumbered(_ translate: (FormID) -> FormID) -> KeywordList {
        var copy = self
        copy.keywords = keywords.map(translate)
        return copy
    }
}

nonisolated extension ModelBaseDetails {
    func renumbered(_ translate: (FormID) -> FormID) -> ModelBaseDetails {
        var copy = self
        copy.model = model?.renumbered(translate)
        copy.destructible = destructible?.renumbered(translate)
        copy.waterType = waterType.renumbered(translate)
        copy.associatedSpell = associatedSpell.renumbered(translate)
        copy.furnitureMarkers = furnitureMarkers.map {
            var marker = $0
            marker.keyword = $0.keyword.renumbered(translate)
            return marker
        }
        copy.randomTeleports = randomTeleports.map(translate)
        return copy
    }
}

nonisolated extension Destructible {
    func renumbered(_ translate: (FormID) -> FormID) -> Destructible {
        var copy = self
        copy.stages = stages.map {
            var stage = $0
            stage.explosion = $0.explosion.renumbered(translate)
            stage.debris = $0.debris.renumbered(translate)
            stage.model = $0.model?.renumbered(translate)
            return stage
        }
        return copy
    }
}
