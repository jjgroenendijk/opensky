// Whole-install field census: each decoded field must be set by at least one
// record of the five masters or the Creation Club plugins. The few fields no
// record sets are pinned. The census goes to `logs/record-field-census.log`.
// Run with `make test-real T='RecordFieldCensusRealDataTests'`.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import Testing

struct RecordFieldCensusRealDataTests {
    /// Fields the install never sets: the raw field is absent, empty, or zero on every
    /// record. Each was checked against the raw bytes.
    private static let neverSet: [String] = [
        "ActorBaseDetails.guardWarnOverride",
        "ActorBaseDetails.observeDeadOverride",
        "AddonNode.sound",
        "BodyPart.goreTextureHashes",
        "BodyPart.limbReplacementModel",
        "BodyPart.poseMatching",
        "BodyPartNodeData.explodableDebris",
        "BodyPartNodeData.explodableExplosion",
        "BodyPartNodeData.explosionChance",
        "BodyPartNodeData.goreOffset",
        "BodyPartNodeData.goreRotation",
        "BodyPartNodeData.severableDebris",
        "BodyPartNodeData.severableDebrisCount",
        "BodyPartNodeData.severableExplosion",
        "BodyPartNodeData.unknown",
        "CellExtras.waterNoiseTexture",
        "Destructible.isVATSTargetable",
        "Explosion.scriptData",
        "GameMessage.unusedIcon",
        "IdleMarker.model",
        "ModelBaseDetails.associatedSpell",
        "ModelBaseDetails.randomTeleports",
        "Patrol.topic",
        "PlacedProjectile.editorID",
        "PlacedProjectile.isInitiallyDisabled",
        "PlacedProjectile.linkedReferences",
        "PlacedReferenceDetails.charge",
        "PlacedReferenceDetails.count",
        "PlacedReferenceDetails.distantLOD",
        "PlacedReferenceDetails.health",
        "PlacedReferenceDetails.linkColors",
        "PlacedReferenceDetails.ownerRank",
        "PlacedReferenceDetails.radius",
        "PlacedReferenceDetails.waterRotationalVelocity",
        "Properties.unknown",
        "RaceHeadData.model",
        "RaceProperties.unknown",
        "SceneAction.unknownLNAM",
        "VolumetricLighting.customColorContribution",
        "WaterCurrentLink.reference",
        "WaterReflection.type",
        "WorldspaceDetails.canopyShadow",
        "WorldspaceDetails.mapImage",
        "WorldspaceDetails.waterNoiseTexture",
        "WorldspaceMapData.usableDimensions"
    ]

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func everyDecodedFieldIsSetOnTheInstall() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        var census = FieldCensus()
        for name in try InstallPlugins.names(root: root) {
            let file = try ESMFile(url: root.dataURL.appending(path: name))
            ESMWalk.forEachRecord(in: file) { record in
                if !record.isDeleted, Self.types.contains(record.type) {
                    let value = try? RecordDecoders.decode(record, localized: file.isLocalized)
                    if let value {
                        census.add(value)
                    }
                }
                return true
            }
        }
        let report = (census.neverSet.map { "[INFO] never set \($0)" } + census.report)
            .joined(separator: "\n")
        try report.write(
            to: RepositoryLogs.directory().appending(path: "record-field-census.log"),
            atomically: true,
            encoding: .utf8
        )
        #expect(census.neverSet == Self.neverSet, "\(census.neverSet)")
        #expect(census.unread.values.reduce(0, +) == 1, "one WTHR DALC is short")
    }

    private static let types: Set<FourCC> = [
        "NPC_", "RACE", "BPTD", "HDPT", "CLFM", "EYES", "CSTY", "CELL", "WRLD", "ACTI", "DOOR",
        "FURN", "FLOR", "TACT", "TREE", "MSTT", "WTHR", "PHZD", "PGRE", "REFR", "ACHR", "CAMS",
        "CPTH", "EFSH", "MATO", "SPGD", "VOLI", "DEBR", "EXPL", "IMGS", "IMAD", "RFCT", "ADDN",
        "HAZD", "SOPM", "REVB", "DLBR", "DLVW", "SCEN", "SMBN", "SMQN", "SMEN", "IDLE", "ANIO",
        "IDLM", "MESG", "LSCR", "PACK", "PERK", "AMMO", "APPA", "BOOK", "INGR", "ALCH", "KEYM"
    ]
}

extension FieldCensus {
    fileprivate mutating func add(_ value: any Sendable) {
        if addActor(value) || addWorld(value) || addEffect(value) || addSound(value) {
            return
        }
        addQuest(value)
    }

    private mutating func addActor(_ value: any Sendable) -> Bool {
        switch value {
        case let actor as ActorBase: countActor(actor)
        case let race as Race: countRace(race)
        case let data as BodyPartData: countBodyParts(data)
        case let part as HeadPart: countHeadPart(part)
        case let color as ColorForm: countColor(color)
        case let eyes as Eyes: countEyes(eyes)
        case let style as CombatStyle: countCombatStyle(style)
        default: return false
        }
        return true
    }

    private mutating func addWorld(_ value: any Sendable) -> Bool {
        switch value {
        case let cell as Cell: countCell(cell)
        case let worldspace as Worldspace: countWorldspace(worldspace)
        case let base as ModelBase: countModelBase(base)
        case let weather as Weather: countWeather(weather)
        case let placed as PlacedProjectile: countProjectile(placed)
        case let reference as PlacedReference: countReference(reference)
        case let actor as PlacedActor: countActorReference(actor)
        default: return false
        }
        return true
    }

    private mutating func addEffect(_ value: any Sendable) -> Bool {
        switch value {
        case let shot as CameraShot: countCameraShot(shot)
        case let path as CameraPath: countCameraPath(path)
        case let shader as EffectShader: countEffectShader(shader)
        case let material as MaterialObject: countMaterial(material)
        case let geometry as ShaderParticleGeometry: countParticles(geometry)
        case let lighting as VolumetricLighting: countVolumetricLighting(lighting)
        case let debris as Debris: countDebris(debris)
        case let explosion as Explosion: countExplosion(explosion)
        case let space as ImageSpace: countImageSpace(space)
        case let adapter as ImageSpaceAdapter: countImageSpaceAdapter(adapter)
        default: return false
        }
        return true
    }

    private mutating func addSound(_ value: any Sendable) -> Bool {
        switch value {
        case let effect as VisualEffect: countVisualEffect(effect)
        case let node as AddonNode: countAddonNode(node)
        case let hazard as Hazard: countHazard(hazard)
        case let model as SoundOutputModel: countOutputModel(model)
        case let reverb as ReverbParameters: countReverb(reverb)
        case let package as Package: countFragments("PACK", package.scriptData)
        case let perk as Perk: countFragments("PERK", perk.script)
        default: return false
        }
        return true
    }

    private mutating func addItem(_ value: any Sendable) -> Bool {
        switch value {
        case let item as Ammunition: countItem(item.fields)
        case let item as Apparatus: countItem(item.fields)
        case let item as Book: countItem(item.fields)
        case let item as Ingredient: countItem(item.fields)
        case let item as Ingestible: countItem(item.fields)
        case let item as KeyItem: countItem(item.fields)
        default: return false
        }
        return true
    }

    private mutating func addQuest(_ value: any Sendable) {
        if addItem(value) {
            return
        }
        switch value {
        case let branch as DialogueBranch: countBranch(branch)
        case let view as DialogueView: countView(view)
        case let scene as Scene: countScene(scene)
        case let node as StoryManagerNode: countStoryNode(node)
        case let idle as IdleAnimation: countIdle(idle)
        case let object as AnimatedObject: countAnimatedObject(object)
        case let marker as IdleMarker: countIdleMarker(marker)
        case let message as GameMessage: countMessage(message)
        case let screen as LoadScreen: countLoadScreen(screen)
        default: break
        }
    }
}
