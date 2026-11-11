// One typed decoder per record type, so a caller can decode any record of the
// install without knowing its Swift type. The coverage sweep and the record
// inspector use it. Layout notes: docs/formats/records.md.

import Foundation
public import OpenSkyFormatsCore

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

    static func plain(_ decode: @escaping @Sendable (ESMRecord) throws -> any Sendable)
        -> Decode
    {
        { record, _ in try decode(record) }
    }

    /// The families share no record type; a shared one stops the table from building.
    private static let table = [FourCC: Decode](
        uniqueKeysWithValues: [
            Items.table, World.table, Sound.table, Effects.table, Actors.table, Dialogue.table
        ].flatMap { family in family.map { ($0.key, $0.value) } }
    )

    private enum Items {
        static let table: [FourCC: Decode] = [
            "AMMO": { try Ammunition(record: $0, localized: $1) },
            "APPA": { try Apparatus(record: $0, localized: $1) },
            "ARMO": { try Armor(record: $0, localized: $1) },
            "ARMA": RecordDecoders.plain { try ArmorAddon(record: $0) },
            "BOOK": { try Book(record: $0, localized: $1) },
            "ALCH": { try Ingestible(record: $0, localized: $1) },
            "INGR": { try Ingredient(record: $0, localized: $1) },
            "KEYM": { try KeyItem(record: $0, localized: $1) },
            "MISC": { try MiscItem(record: $0, localized: $1) },
            "SLGM": { try SoulGem(record: $0, localized: $1) },
            "SCRL": { try Scroll(record: $0, localized: $1) },
            "WEAP": { try Weapon(record: $0, localized: $1) },
            "CONT": { try Container(record: $0, localized: $1) },
            "COBJ": RecordDecoders.plain { try ConstructibleObject(record: $0) },
            "OTFT": RecordDecoders.plain { try Outfit(record: $0) },
            "LVLI": RecordDecoders.plain { try LeveledList(record: $0) },
            "LVLN": RecordDecoders.plain { try LeveledList(record: $0) },
            "LVSP": RecordDecoders.plain { try LeveledList(record: $0) },
            "FLST": RecordDecoders.plain { try FormList(record: $0) },
            "KYWD": RecordDecoders.plain { try Keyword(record: $0) },
            "AACT": RecordDecoders.plain { try ActionRecord(record: $0) },
            "EQUP": RecordDecoders.plain { try EquipSlot(record: $0) },
            "TXST": RecordDecoders.plain { try TextureSet(record: $0) },
            "ARTO": RecordDecoders.plain { try ArtObject(record: $0) },
            "TES4": RecordDecoders.plain { try PluginHeader(tes4: $0) }
        ]
    }

    private enum World {
        static let table: [FourCC: Decode] = [
            "ACTI": { try ModelBase(record: $0, localized: $1) },
            "DOOR": { try ModelBase(record: $0, localized: $1) },
            "FURN": { try ModelBase(record: $0, localized: $1) },
            "FLOR": { try ModelBase(record: $0, localized: $1) },
            "TACT": { try ModelBase(record: $0, localized: $1) },
            "TREE": { try ModelBase(record: $0, localized: $1) },
            "MSTT": { try ModelBase(record: $0, localized: $1) },
            "STAT": RecordDecoders.plain { try StaticObject(record: $0) },
            "GRAS": RecordDecoders.plain { try Grass(record: $0) },
            "LIGH": { try LightRecord(record: $0, localized: $1) },
            "CELL": { try Cell(record: $0, localized: $1) },
            "WRLD": { try Worldspace(record: $0, localized: $1) },
            "LAND": RecordDecoders.plain { try Land(record: $0) },
            "LTEX": RecordDecoders.plain { try LandTexture(record: $0) },
            "NAVM": RecordDecoders.plain { try Navmesh(record: $0) },
            "NAVI": RecordDecoders.plain { try NavmeshInfoMap(record: $0) },
            "REFR": RecordDecoders.plain { try PlacedReference(record: $0) },
            "ACHR": RecordDecoders.plain { try PlacedActor(record: $0) },
            "PHZD": RecordDecoders.plain { try PlacedProjectile(record: $0) },
            "PGRE": RecordDecoders.plain { try PlacedProjectile(record: $0) },
            "REGN": { try Region(record: $0, localized: $1) },
            "LCTN": { try Location(record: $0, localized: $1) },
            "LCRT": RecordDecoders.plain { try LocationRefType(record: $0) },
            "ECZN": RecordDecoders.plain { try EncounterZone(record: $0) },
            "CLMT": RecordDecoders.plain { try Climate(record: $0) },
            "WTHR": RecordDecoders.plain { try Weather(record: $0) },
            "WATR": { try WaterType(record: $0, localized: $1) },
            "LGTM": RecordDecoders.plain { try LightingTemplate(record: $0) },
            "COLL": { try CollisionLayer(record: $0, localized: $1) },
            "DOBJ": RecordDecoders.plain { try DefaultObjects(record: $0) },
            "GLOB": RecordDecoders.plain { try Global(record: $0) },
            "GMST": { try GameSetting(record: $0, localized: $1) },
            "LSCR": { try LoadScreen(record: $0, localized: $1) },
            "MESG": { try GameMessage(record: $0, localized: $1) },
            "CAMS": RecordDecoders.plain { try CameraShot(record: $0) },
            "CPTH": RecordDecoders.plain { try CameraPath(record: $0) }
        ]
    }

    private enum Sound {
        static let table: [FourCC: Decode] = [
            "ASPC": RecordDecoders.plain { try AcousticSpace(record: $0) },
            "SOUN": RecordDecoders.plain { try SoundMarker(record: $0) },
            "SNDR": RecordDecoders.plain { try SoundDescriptor(record: $0) },
            "SNCT": { try SoundCategory(record: $0, localized: $1) },
            "SOPM": RecordDecoders.plain { try SoundOutputModel(record: $0) },
            "REVB": RecordDecoders.plain { try ReverbParameters(record: $0) },
            "MUSC": RecordDecoders.plain { try MusicType(record: $0) },
            "MUST": RecordDecoders.plain { try MusicTrack(record: $0) },
            "FSTP": RecordDecoders.plain { try Footstep(record: $0) },
            "FSTS": RecordDecoders.plain { try FootstepSet(record: $0) },
            "MATT": RecordDecoders.plain { try MaterialType(record: $0) }
        ]
    }

    private enum Effects {
        static let table: [FourCC: Decode] = [
            "MGEF": { try MagicEffect(record: $0, localized: $1) },
            "SPEL": { try Spell(record: $0, localized: $1) },
            "ENCH": { try Enchantment(record: $0, localized: $1) },
            "SHOU": { try Shout(record: $0, localized: $1) },
            "WOOP": { try WordOfPower(record: $0, localized: $1) },
            "PERK": { try Perk(record: $0, localized: $1) },
            "AVIF": { try ActorValueInformation(record: $0, localized: $1) },
            "DUAL": RecordDecoders.plain { try DualCastData(record: $0) },
            "PROJ": { try Projectile(record: $0, localized: $1) },
            "EXPL": { try Explosion(record: $0, localized: $1) },
            "DEBR": RecordDecoders.plain { try Debris(record: $0) },
            "HAZD": { try Hazard(record: $0, localized: $1) },
            "IPCT": RecordDecoders.plain { try Impact(record: $0) },
            "IPDS": RecordDecoders.plain { try ImpactDataSet(record: $0) },
            "EFSH": RecordDecoders.plain { try EffectShader(record: $0) },
            "ADDN": RecordDecoders.plain { try AddonNode(record: $0) },
            "RFCT": RecordDecoders.plain { try VisualEffect(record: $0) },
            "SPGD": RecordDecoders.plain { try ShaderParticleGeometry(record: $0) },
            "VOLI": RecordDecoders.plain { try VolumetricLighting(record: $0) },
            "MATO": RecordDecoders.plain { try MaterialObject(record: $0) },
            "IMGS": RecordDecoders.plain { try ImageSpace(record: $0) },
            "IMAD": RecordDecoders.plain { try ImageSpaceAdapter(record: $0) }
        ]
    }

    private enum Actors {
        static let table: [FourCC: Decode] = [
            "NPC_": { try ActorBase(record: $0, localized: $1) },
            "RACE": { try Race(record: $0, localized: $1) },
            "CLAS": { try CharacterClass(record: $0, localized: $1) },
            "FACT": { try Faction(record: $0, localized: $1) },
            "RELA": RecordDecoders.plain { try Relationship(record: $0) },
            "ASTP": RecordDecoders.plain { try AssociationType(record: $0) },
            "VTYP": RecordDecoders.plain { try VoiceType(record: $0) },
            "HDPT": { try HeadPart(record: $0, localized: $1) },
            "CLFM": { try ColorForm(record: $0, localized: $1) },
            "EYES": { try Eyes(record: $0, localized: $1) },
            "BPTD": { try BodyPartData(record: $0, localized: $1) },
            "MOVT": RecordDecoders.plain { try MovementType(record: $0) },
            "CSTY": RecordDecoders.plain { try CombatStyle(record: $0) },
            "IDLE": RecordDecoders.plain { try IdleAnimation(record: $0) },
            "ANIO": RecordDecoders.plain { try AnimatedObject(record: $0) },
            "IDLM": RecordDecoders.plain { try IdleMarker(record: $0) },
            "PACK": RecordDecoders.plain { try PackageDecoder.decode($0) }
        ]
    }

    private enum Dialogue {
        static let table: [FourCC: Decode] = [
            "QUST": { try Quest(record: $0, localized: $1) },
            "DIAL": { try DialogueTopic(record: $0, localized: $1) },
            "INFO": { try TopicInfo(record: $0, localized: $1) },
            "DLBR": RecordDecoders.plain { try DialogueBranch(record: $0) },
            "DLVW": RecordDecoders.plain { try DialogueView(record: $0) },
            "SCEN": RecordDecoders.plain { try Scene(record: $0) },
            "SMBN": RecordDecoders.plain { try StoryManagerNode(record: $0) },
            "SMQN": RecordDecoders.plain { try StoryManagerNode(record: $0) },
            "SMEN": RecordDecoders.plain { try StoryManagerNode(record: $0) }
        ]
    }
}
