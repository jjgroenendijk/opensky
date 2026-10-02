// One typed decoder per record type, so a caller can decode any record of the
// install without knowing its Swift type. The coverage sweep and the record
// inspector use it. Layout notes: docs/formats/records.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public enum RecordDecoders {
    /// Decodes one record. The flag is the TES4 localized flag of its plugin.
    public typealias Decode = @Sendable (ESMRecord, Bool) throws -> any Sendable

    /// The decoder of a record type, or nil when the type has none.
    public static func decoder(for type: FourCC) -> Decode? {
        table[type]
    }

    public static var decodedTypes: Set<FourCC> {
        Set(table.keys)
    }

    /// Decodes `record` with the decoder of its type.
    public static func decode(_ record: ESMRecord, localized: Bool) throws -> any Sendable {
        guard let decode = table[record.type] else {
            throw ESMError.malformed("no decoder for record type \(record.type)")
        }
        return try decode(record, localized)
    }

    private static func plain(_ decode: @escaping @Sendable (ESMRecord) throws -> any Sendable)
        -> Decode
    {
        { record, _ in try decode(record) }
    }

    private static let table: [FourCC: Decode] = items.merging(world) { first, _ in first }
        .merging(effects) { first, _ in first }
        .merging(actors) { first, _ in first }
        .merging(dialogue) { first, _ in first }

    private static let items: [FourCC: Decode] = [
        "AMMO": { try Ammunition(record: $0, localized: $1) },
        "APPA": { try Apparatus(record: $0, localized: $1) },
        "ARMO": { try Armor(record: $0, localized: $1) },
        "ARMA": plain { try ArmorAddon(record: $0) },
        "BOOK": { try Book(record: $0, localized: $1) },
        "ALCH": { try Ingestible(record: $0, localized: $1) },
        "INGR": { try Ingredient(record: $0, localized: $1) },
        "KEYM": { try KeyItem(record: $0, localized: $1) },
        "MISC": { try MiscItem(record: $0, localized: $1) },
        "SLGM": { try SoulGem(record: $0, localized: $1) },
        "SCRL": { try Scroll(record: $0, localized: $1) },
        "WEAP": { try Weapon(record: $0, localized: $1) },
        "CONT": { try Container(record: $0, localized: $1) },
        "COBJ": plain { try ConstructibleObject(record: $0) },
        "OTFT": plain { try Outfit(record: $0) },
        "LVLI": plain { try LeveledList(record: $0) },
        "LVLN": plain { try LeveledList(record: $0) },
        "LVSP": plain { try LeveledList(record: $0) },
        "FLST": plain { try FormList(record: $0) },
        "KYWD": plain { try Keyword(record: $0) },
        "AACT": plain { try ActionRecord(record: $0) },
        "EQUP": plain { try EquipSlot(record: $0) },
        "TXST": plain { try TextureSet(record: $0) },
        "ARTO": plain { try ArtObject(record: $0) },
        "TES4": plain { try PluginHeader(tes4: $0) }
    ]

    private static let world: [FourCC: Decode] = [
        "ACTI": { try ModelBase(record: $0, localized: $1) },
        "DOOR": { try ModelBase(record: $0, localized: $1) },
        "FURN": { try ModelBase(record: $0, localized: $1) },
        "FLOR": { try ModelBase(record: $0, localized: $1) },
        "TACT": { try ModelBase(record: $0, localized: $1) },
        "TREE": { try ModelBase(record: $0, localized: $1) },
        "MSTT": { try ModelBase(record: $0, localized: $1) },
        "STAT": plain { try StaticObject(record: $0) },
        "GRAS": plain { try Grass(record: $0) },
        "LIGH": plain { try LightRecord(record: $0) },
        "CELL": { try Cell(record: $0, localized: $1) },
        "WRLD": { try Worldspace(record: $0, localized: $1) },
        "LAND": plain { try Land(record: $0) },
        "LTEX": plain { try LandTexture(record: $0) },
        "NAVM": plain { try Navmesh(record: $0) },
        "NAVI": plain { try NavmeshInfoMap(record: $0) },
        "REFR": plain { try PlacedReference(record: $0) },
        "ACHR": plain { try PlacedActor(record: $0) },
        "PHZD": plain { try PlacedProjectile(record: $0) },
        "PGRE": plain { try PlacedProjectile(record: $0) },
        "REGN": plain { try Region(record: $0) },
        "LCTN": { try Location(record: $0, localized: $1) },
        "LCRT": plain { try LocationRefType(record: $0) },
        "ECZN": plain { try EncounterZone(record: $0) },
        "CLMT": plain { try Climate(record: $0) },
        "WTHR": plain { try Weather(record: $0) },
        "WATR": plain { try WaterType(record: $0) },
        "LGTM": plain { try LightingTemplate(record: $0) },
        "ASPC": plain { try AcousticSpace(record: $0) },
        "SOUN": plain { try SoundMarker(record: $0) },
        "SNDR": plain { try SoundDescriptor(record: $0) },
        "SNCT": { try SoundCategory(record: $0, localized: $1) },
        "SOPM": plain { try SoundOutputModel(record: $0) },
        "REVB": plain { try ReverbParameters(record: $0) },
        "MUSC": plain { try MusicType(record: $0) },
        "MUST": plain { try MusicTrack(record: $0) },
        "FSTP": plain { try Footstep(record: $0) },
        "FSTS": plain { try FootstepSet(record: $0) },
        "MATT": plain { try MaterialType(record: $0) },
        "COLL": { try CollisionLayer(record: $0, localized: $1) },
        "DOBJ": plain { try DefaultObjects(record: $0) },
        "GLOB": plain { try Global(record: $0) },
        "GMST": { try GameSetting(record: $0, localized: $1) },
        "LSCR": { try LoadScreen(record: $0, localized: $1) },
        "MESG": { try GameMessage(record: $0, localized: $1) },
        "CAMS": plain { try CameraShot(record: $0) },
        "CPTH": plain { try CameraPath(record: $0) }
    ]

    private static let effects: [FourCC: Decode] = [
        "MGEF": { try MagicEffect(record: $0, localized: $1) },
        "SPEL": { try Spell(record: $0, localized: $1) },
        "ENCH": { try Enchantment(record: $0, localized: $1) },
        "SHOU": { try Shout(record: $0, localized: $1) },
        "WOOP": { try WordOfPower(record: $0, localized: $1) },
        "PERK": { try Perk(record: $0, localized: $1) },
        "AVIF": { try ActorValueInformation(record: $0, localized: $1) },
        "DUAL": plain { try DualCastData(record: $0) },
        "PROJ": plain { try Projectile(record: $0) },
        "EXPL": { try Explosion(record: $0, localized: $1) },
        "DEBR": plain { try Debris(record: $0) },
        "HAZD": { try Hazard(record: $0, localized: $1) },
        "IPCT": plain { try Impact(record: $0) },
        "IPDS": plain { try ImpactDataSet(record: $0) },
        "EFSH": plain { try EffectShader(record: $0) },
        "ADDN": plain { try AddonNode(record: $0) },
        "RFCT": plain { try VisualEffect(record: $0) },
        "SPGD": plain { try ShaderParticleGeometry(record: $0) },
        "VOLI": plain { try VolumetricLighting(record: $0) },
        "MATO": plain { try MaterialObject(record: $0) },
        "IMGS": plain { try ImageSpace(record: $0) },
        "IMAD": plain { try ImageSpaceAdapter(record: $0) }
    ]

    private static let actors: [FourCC: Decode] = [
        "NPC_": { try ActorBase(record: $0, localized: $1) },
        "RACE": { try Race(record: $0, localized: $1) },
        "CLAS": { try CharacterClass(record: $0, localized: $1) },
        "FACT": { try Faction(record: $0, localized: $1) },
        "RELA": plain { try Relationship(record: $0) },
        "ASTP": plain { try AssociationType(record: $0) },
        "VTYP": plain { try VoiceType(record: $0) },
        "HDPT": { try HeadPart(record: $0, localized: $1) },
        "CLFM": { try ColorForm(record: $0, localized: $1) },
        "EYES": { try Eyes(record: $0, localized: $1) },
        "BPTD": { try BodyPartData(record: $0, localized: $1) },
        "MOVT": plain { try MovementType(record: $0) },
        "CSTY": plain { try CombatStyle(record: $0) },
        "IDLE": plain { try IdleAnimation(record: $0) },
        "ANIO": plain { try AnimatedObject(record: $0) },
        "IDLM": plain { try IdleMarker(record: $0) },
        "PACK": plain { try PackageDecoder.decode($0) }
    ]

    private static let dialogue: [FourCC: Decode] = [
        "QUST": { try Quest(record: $0, localized: $1) },
        "DIAL": { try DialogueTopic(record: $0, localized: $1) },
        "INFO": { try TopicInfo(record: $0, localized: $1) },
        "DLBR": plain { try DialogueBranch(record: $0) },
        "DLVW": plain { try DialogueView(record: $0) },
        "SCEN": plain { try Scene(record: $0) },
        "SMBN": plain { try StoryManagerNode(record: $0) },
        "SMQN": plain { try StoryManagerNode(record: $0) },
        "SMEN": plain { try StoryManagerNode(record: $0) }
    ]
}
