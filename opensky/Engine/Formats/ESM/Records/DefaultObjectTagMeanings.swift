// Human-readable DOBJ use-tag names transcribed from xEdit dev-4.1.6
// Core/wbDefinitionsTES5.pas `wbDOBJObjectsTES5`, lines 6560-6934.
// Keeping the complete table lets the decoder tally a mod-introduced tag
// without rejecting the entry or pretending it has known engine semantics.

import Foundation

nonisolated extension DefaultObjectTag {
    static let knownMeanings: [FourCC: String] = {
        let source = """
        AAAC	Action - Activate
        AAB1	Action - Bleedout Start
        AAB2	Action - Bleedout Stop
        AABA	Action - Block Anticipate
        AABH	Action - Block Hit
        AABI	Action - Bumped Into
        AADE	Action - Death
        AADW	Action - Death Wait
        AADR	Action - Draw
        ADPA	Action - Dual Power Attack
        AADA	Action - Dual Attack
        AADL	Action - Dual Release
        AAFA	Action - Fall
        AAF1	Action - Fly Start
        AAF2	Action - Fly Stop
        AAFQ	Action - Force Equip
        AAGU	Action - Get Up
        AAH1	Action - Hover Start
        AAH2	Action - Hover Stop
        AAID	Action - Idle
        AAIS	Action - Idle Stop
        ASID	Action - Idle Stop Instant
        AIDW	Action - Idle Warn
        AAJP	Action - Jump
        AKDN	Action - Knockdown
        AALN	Action - Land
        AALM	Action - Large Movement Delta
        AAR2	Action - Large Recoil
        ALPA	Action - Left Power Attack
        AALA	Action - Left Attack
        AALI	Action - Left Interrupt
        AALD	Action - Left Ready
        AALR	Action - Left Release
        ALTI	Action - Listen Idle
        AALK	Action - Look
        AMBK	Action - Move Backward
        AMFD	Action - Move Forward
        AMLT	Action - Move Left
        AMRT	Action - Move Right
        AMST	Action - Move Start
        AMSP	Action - Move Stop
        AAPE	Action - Path End
        AAPS	Action - Path Start
        ARGI	Action - Ragdoll Instant
        AARC	Action - Recoil
        AREL	Action - Reload
        ARAG	Action - Reset Animation Graph
        AAPA	Action - Right Power Attack
        AARA	Action - Right Attack
        AARI	Action - Right Interrupt
        AARD	Action - Right Ready
        AARR	Action - Right Release
        AASH	Action - Sheath
        AASC	Action - Shield Change
        AASN	Action - Sneak
        AAST	Action - Sprint Start
        AASP	Action - Sprint Stop
        AAS1	Action - Stagger Start
        AASS	Action - Summoned Start
        AASW	Action - Swim State Change
        ATKI	Action - Talking Idle
        ATLE	Action - Turn Left
        ATRI	Action - Turn Right
        ATSP	Action - Turn Stop
        AAVC	Action - Voice
        AAVI	Action - Voice Interrupt
        AAVD	Action - Voice Ready
        AAVR	Action - Voice Release
        AAWH	Action - Ward Hit
        AWWS	Action - Waterwalk Start
        APSH	Allow Player Shout
        ARTL	Armor Material List
        ABSE	Art Object - Absorb Effect
        ALDM	Ash LOD Material
        ALHD	Ash LOD Material (HD)
        BENA	Base Armor Enchantment
        BAPS	Base Poison
        BAPO	Base Potion
        BENW	Base Weapon Enchantment
        AWWW	Bunny Faction
        CSTY	Combat Style
        CACA	Commanded Actor Ability
        CMPX	Complex Scene Object
        DBHF	Dark Brotherhood Faction
        DMFL	Default MovementType - Fly
        DMRN	Default MovementType - Run
        DMSN	Default MovementType - Sneak
        DMSP	Default MovementType - Sprint
        DMSW	Default MovementType - Swim
        DMWL	Default MovementType - Walk
        PLST	Default Pack List
        DOP2	Dialogue Output Model (2D)
        DOP3	Dialogue Output Model (3D)
        DDSC	Dialogue Voice Category
        DGFL	Dialogue Follower Quest
        DCZM	Dragon Crash Zone Marker
        DLZM	Dragon Land Zone Marker
        DMXL	Dragon Mount No Land List
        DEIS	Drug Wears Off Image Space
        EPDF	Eat Package Default Food
        EHEQ	Equip - Either Hand
        LHEQ	Equip - Left Hand
        POEQ	Equip - Potion
        RHEQ	Equip - Right Hand
        VOEQ	Equip - Voice
        EACA	Every Actor Ability
        FPCL	Favor - Cost Large
        FPCM	Favor - Cost Medium
        FPCS	Favor - Cost Small
        FGPD	Favor - Gifts Per Day
        FTML	Favor - Travel Marker Location
        FTRF	Female Face Texture Set: Eyes
        FTHF	Female Face Texture Set: Head
        FTMF	Female Face Texture Set: Mouth
        FTGF	Fighters' Guild Faction
        FMYS	Flying Mount - Allowed Spells
        FMNS	Flying Mount - Disallowed Spells
        FMFF	Flying Mount - Fly Fast Worldspaces
        DFTS	Footstep Set
        HCLL	FormList - Hair Color List
        FTNP	Furniture Test NPC
        GOLD	Gold
        GFAC	Guard Faction
        HVFS	Harvest Failed Sound
        HVSS	Harvest Sound
        HFSD	Heartbeat Sound Fast
        HSSD	Heartbeat Sound Slow
        HBAT	Help - Attack Target
        HBBR	Help - Barter
        HBAL	Help - Basic Alchemy
        HBCO	Help - Basic Cooking
        HBEC	Help - Basic Enchanting
        HBFG	Help - Basic Forging
        HBLX	Help - Basic Lockpicking (Console)
        HBLK	Help - Basic Lockpicking (PC)
        HBOC	Help - Basic Object Creation
        HBML	Help - Basic Smelting
        HBSA	Help - Basic Smithing Armor
        HBSM	Help - Basic Smithing Weapon
        HBTA	Help - Basic Tanning
        HBFS	Help - Favorites
        HBFM	Help - Flying Mount
        HBHJ	Help - Jail
        HBJL	Help - Journal
        HBLU	Help - Leveling up
        HBLH	Help - Low Health
        HBLM	Help - Low Magicka
        HBLS	Help - Low Stamina
        HBMM	Help - Map Menu
        HBSK	Help - Skills Menu
        HBTL	Help - Target Lock
        HBFT	Help - Teammate Favor
        HBWC	Help - Weapon Charge
        HMAE	Help Manual - Creation Club AE
        HMCC	Help Manual - Creation Club
        HMPC	Help Manual - PC
        HMXB	Help Manual - XBox
        IMID	ImageSpaceModifier For Inventory Menu.
        LSIS	Imagespace: Load screen
        IMLH	Imagespace: Low Health
        IOPM	Interface Output Model
        INVP	Inventory Player
        JRLF	Jarl Faction
        AFNP	Keyword - Activator Furniture No Player
        ANML	Keyword - Animal
        AODA	Keyword - Armor Material Daedric
        AODB	Keyword - Armor Material Dragonbone
        AODP	Keyword - Armor Material Dragonplate
        AODS	Keyword - Armor Material Dragonscale
        AODW	Keyword - Armor Material Dwarven
        AOEB	Keyword - Armor Material Ebony
        AOEL	Keyword - Armor Material Elven
        AOES	Keyword - Armor Material Elven Splinted
        AOFL	Keyword - Armor Material FullLeather
        AOGL	Keyword - Armor Material Glass
        AHBM	Keyword - Armor Material Heavy Bonemold
        AHCH	Keyword - Armor Material Heavy Chitin
        AHNC	Keyword - Armor Material Heavy Nordic
        AHSM	Keyword - Armor Material Heavy Stalhrim
        AOHI	Keyword - Armor Material Hide
        AOIM	Keyword - Armor Material Imperial
        AOIH	Keyword - Armor Material Imperial Heavy
        AOIR	Keyword - Armor Material Imperial Reinforced
        AOFE	Keyword - Armor Material Iron
        AOIB	Keyword - Armor Material Iron Banded
        ALBM	Keyword - Armor Material Light Bonemold
        ALCH	Keyword - Armor Material Light Chitin
        ALNC	Keyword - Armor Material Light Nordic
        ALSM	Keyword - Armor Material Light Stalhrim
        AOOR	Keyword - Armor Material Orcish
        AOSC	Keyword - Armor Material Scaled
        AOST	Keyword - Armor Material Steel
        AOSP	Keyword - Armor Material Steel Plate
        AOSK	Keyword - Armor Material Stormcloak
        AOSD	Keyword - Armor Material Studded
        KWBR	Keyword - BeastRace
        CWNE	Keyword - Civil War Neutral
        CWOK	Keyword - Civil War Owner
        KWDO	Keyword - ClearableLocation
        COEX	Keyword - Conditional Explosion
        COOK	Keyword - Cooking Pot
        KWCU	Keyword - Cuirass
        DAED	Keyword - Daedra
        DIEN	Keyword - Disallow Enchanting
        DRAK	Keyword - Dragon
        KWDM	Keyword - Dummy Object
        FORG	Keyword - Forge
        FFFP	Keyword - Furniture Forces 1st Person
        FFTP	Keyword - Furniture Forces 3rd Person
        GCK1	Keyword - Generic Craftable Keyword 01
        GCK2	Keyword - Generic Craftable Keyword 02
        GCK3	Keyword - Generic Craftable Keyword 03
        GCK4	Keyword - Generic Craftable Keyword 04
        GCK5	Keyword - Generic Craftable Keyword 05
        GCK6	Keyword - Generic Craftable Keyword 06
        GCK7	Keyword - Generic Craftable Keyword 07
        GCK8	Keyword - Generic Craftable Keyword 08
        GCK9	Keyword - Generic Craftable Keyword 09
        GCKX	Keyword - Generic Craftable Keyword 10
        LKHO	Keyword - Hold Location
        HRSK	Keyword - Horse
        JWLR	Keyword - Jewelry
        MNTK	Keyword - Mount
        MNT2	Keyword - Mount Dragon
        MVBL	Keyword - Movable
        KWMS	Keyword - Must Stop
        NPCK	Keyword - NPC
        NRNT	Keyword - Nirnroot
        RUSG	Keyword - Reusable SoulGem
        BEEP	Keyword - Robot
        SAT1	Keyword - Scale Actor To 1.0
        KWOT	Keyword - Skip Outfit Items
        SMLT	Keyword - Smelter
        SPFK	Keyword - Special Furniture
        TANN	Keyword - Tanning Rack
        TKAM	Keyword - Type Ammo
        TKAR	Keyword - Type Armor
        TKBK	Keyword - Type Book
        TKIG	Keyword - Type Ingredient
        TKKY	Keyword - Type Key
        TKMS	Keyword - Type Misc
        TKPT	Keyword - Type Potion
        TKSG	Keyword - Type Soul Gem
        TKWP	Keyword - Type Weapon
        UNDK	Keyword - Undead
        KWUA	Keyword - Update During Archery
        KWGE	Keyword - Use Geometry Emitter
        VAMP	Keyword - Vampire
        WMDA	Keyword - Weapon Material Daedric
        WMDR	Keyword - Weapon Material Draugr
        WMDH	Keyword - Weapon Material Draugr Honed
        WMDW	Keyword - Weapon Material Dwarven
        WMEB	Keyword - Weapon Material Ebony
        WMEL	Keyword - Weapon Material Elven
        WMFA	Keyword - Weapon Material Falmer
        WMFH	Keyword - Weapon Material Falmer Honed
        WMGL	Keyword - Weapon Material Glass
        WMIM	Keyword - Weapon Material Imperial
        WMIR	Keyword - Weapon Material Iron
        WPNC	Keyword - Weapon Material Nordic
        WMOR	Keyword - Weapon Material Orcish
        WPSM	Keyword - Weapon Material Stalhrim
        WMST	Keyword - Weapon Material Steel
        WMWO	Keyword - Weapon Material Wood
        WTBA	Keyword - Weapon Type Bound Arrow
        KHFL	Kinect Help FormList
        DLMT	Landscape Material
        LRSO	LocRefType - Civil War Soldier
        LRRD	LocRefType - Resource Destructible
        LRTB	LocRefType - Boss
        LMHP	Local Map Hide Plane
        LKPK	Lockpick
        MGGF	Mages' Guild Faction
        MFSN	Magic Fail Sound
        MMCL	Main Menu Cell
        FTEL	Male Face Texture Set: Eyes
        FTHD	Male Face Texture Set: Head
        FTMO	Male Face Texture Set: Mouth
        MMSD	Map Menu Looping Sound
        MTSC	Master Sound Category
        MHFL	Mods Help Form List
        BTMS	Music - Battle
        DTMS	Music - Death
        DFMS	Music - Default
        DCMS	Music - Dungeon Cleared
        LUMS	Music - Level Up
        MDSC	Music - Sound Category
        SSSC	Music - Stats
        SCMS	Music - Success
        NASD	No-Activation Sound
        NDSC	Non-Dialogue Voice Category
        PTEM	Package Template
        PTNP	Pathing Test NPC
        PDLC	Pause During Loading Menu Category
        PDMC	Pause During Menu Category (Fade)
        PIMC	Pause During Menu Category (Immediate)
        PLOC	PersistAll Location
        PUSA	Pickup Sound Armor
        PUSB	Pickup Sound Book
        PUSG	Pickup Sound Generic
        PUSI	Pickup Sound Ingredient
        PUSW	Pickup Sound Weapon
        PCMD	Player Can Mount Dragon Here List
        PFAC	Player Faction
        PIVV	Player Is Vampire Variable
        PIWV	Player Is Werewolf Variable
        PVFA	Player Voice (Female)
        PVFC	Player Voice (Female Child)
        PVMA	Player Voice (Male)
        PVMC	Player Voice (Male Child)
        POPM	Player's Output Model (1st Person)
        P3OM	Player's Output Model (3rd Person)
        PTFR	Potential Follower Faction
        PDSA	Putdown Sound Armor
        PDSB	Putdown Sound Book
        PDSG	Putdown Sound Generic
        PDSI	Putdown Sound Ingredient
        PDSW	Putdown Sound Weapon
        RVBT	Reverb Type
        NMRD	Road Marker
        SFDC	SFX To Fade In Dialogue Category
        SFSN	Shout Fail Sound
        SALT	Sitting Angle Limit
        SKLK	Skeleton Key
        KWSP	Skyrim - Worldspace
        SLDM	Snow LOD Material
        SLHD	Snow LOD Material (HD)
        SCSD	Soul Captured Sound
        SMSC	Stats Mute Category
        SRCP	Survival - Cold Penalty
        SRHP	Survival - Hunger Penalty
        SKAB	Survival - Keyword Armor Body
        SKAF	Survival - Keyword Armor Feet
        SKAH	Survival - Keyword Armor Hands
        SKAO	Survival - Keyword Armor Head
        SKCB	Survival - Keyword Clothing Body
        SKCF	Survival - Keyword Clothing Feet
        SKCH	Survival - Keyword Clothing Hands
        SKCO	Survival - Keyword Clothing Head
        SKCD	Survival - Keyword Cold
        SKWM	Survival - Keyword Warm
        SRSP	Survival - Sleep Penalty
        SRTP	Survival - Temperature
        SRVE	Survival Mode - Enabled
        SRVS	Survival Mode - Show Option
        SRVT	Survival Mode - Toggle
        TKGS	Telekinesis Grab Sound
        TKTS	Telekinesis Throw Sound
        TVGF	Thieves' Guild Faction
        TSSC	Time Sensitive Sound Category
        UWLS	Underwater Loop Sound
        URVT	Underwater Reverb Type
        AVVP	Vampire Available Perks
        VFNC	Vampire Feed No Crime Faction
        RIVR	Vampire Race
        RIVS	Vampire Spells
        AIVC	Verlet Cape
        VLOC	Virtual Location
        PWFD	Wait-For-Dialogue Package
        WASN	Ward Absorb Sound
        WBSN	Ward Break Sound
        WDSN	Ward Deflect Sound
        WEML	Weapon Material List
        AVWP	Werewolf Available Perks
        RIWR	Werewolf Race
        WWSP	Werewolf Spell
        WMWE	World Map Weather
        MORP	Unused - MORP
        MYSF	Unused - MYSF
        MYSN	Unused - MYSN
        PPAR	Unused - PPAR
        RADA	Unused - RADA
        """
        var result: [FourCC: String] = [:]
        for line in source.split(separator: "\n") {
            let columns = line.split(separator: "\t", maxSplits: 1)
            guard
                columns.count == 2,
                let tag = DefaultObjectTag(name: String(columns[0]))
            else { continue }
            result[tag.code] = String(columns[1])
        }
        return result
    }()
}
